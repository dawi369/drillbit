import { personalizationInstructions } from "./prompts/personalization";
import { guidanceModeSchema, teachingPolicy, truthfulVoiceProgress, TEACHING_VERSION } from "./prompts/teaching";
import { spokenHistory, questionReference, voiceDelegationMessages } from "./prompts/voice-context";
import { questionTerminology, practicePersonality } from "./prompts/interviewer";
import { z } from 'zod';
import { Fault, timestamp, practiceProfileSchema } from './domain';
import { consumeUsage, type Env } from './platform';
import { ownedChallenge, settingsFor } from './store';
import { interviewFor } from './interview';
import { historicalSnapshot } from './history';
import { provider, recordUsage, interviewModelSchema } from './ai';
import { xmlContext } from './context';

export const voiceStartSchema = z.object({practiceProfile:practiceProfileSchema.optional(),guidanceMode:guidanceModeSchema.optional(),sdp:z.string().min(1).max(64000),revision:z.number().int().nonnegative()});
export const voiceFragmentSchema = z.object({id:z.string().min(1).max(160),sequence:z.number().int().nonnegative().max(5999),speaker:z.enum(['user','assistant']),text:z.string().max(8000),startMs:z.number().int().nonnegative(),endMs:z.number().int().nonnegative()}).refine(x=>x.endMs>=x.startMs);
export const voiceEventsSchema = z.object({fragments:z.array(voiceFragmentSchema).max(100),closed:z.boolean().optional(),finalized:z.boolean().optional(),usageSeconds:z.number().nonnegative().max(86400).optional()});
export const voiceDelegateSchema = z.object({id:z.string().min(1).max(160)});
export const voiceInstructions = `${questionTerminology}
${practicePersonality}
<interview>Discuss only visible requirements. Do not invent evaluation criteria. Delegate substantive technical feedback, corrections, examples and hints to the backend. Use its guidance naturally, briefly, then listen. Don't narrate delegation or read XML. Do not claim to save, finish or change the exercise; the app owns those actions. Typed drafts are separate from speech. Conversation history may include interrupted or unheard assistant words; don't assume they were heard.</interview>`;
async function sessionFor(env:Env, account:string, challenge:string, id:string) {
 await ownedChallenge(env,account,challenge);
 const s=await env.DB.prepare('SELECT * FROM voice_sessions WHERE id=? AND account_id=? AND challenge_id=?').bind(id,account,challenge).first<any>();
 if(!s) throw new Fault('not_found',404,'Voice session not found.');
 return s;
}
function unlimitedVoice(env: Env, account: string): boolean {
 return (env.VOICE_UNLIMITED_ACCOUNTS ?? '').split(',').map(id => id.trim()).filter(Boolean).includes(account);
}
async function consumeVoiceUsage(env: Env, account: string, kind: string, limit: number) {
 if (!unlimitedVoice(env, account)) return consumeUsage(env, account, kind, limit);
 // Explicit account exemptions retain accounting for every voice operation.
 await env.DB.prepare("INSERT INTO usage(account_id,day,kind,count) VALUES(?,?,?,1) ON CONFLICT(account_id,day,kind) DO UPDATE SET count=count+1").bind(account,timestamp().slice(0,10),kind).run();
}
export async function voiceCapability(env: Env, account: string) {
 const checkedAt = timestamp();
 if (env.VOICE_ENABLED !== 'true' || !env.OPENAI_API_KEY)
  return { available: false, reason: 'Live voice is currently unavailable. You can continue in text.', checkedAt };
 if (unlimitedVoice(env, account)) return { available: true, checkedAt };
 const usage = await env.DB.prepare("SELECT count FROM usage WHERE account_id=? AND day=? AND kind='voice_start'").bind(account, checkedAt.slice(0,10)).first<{count:number}>();
 if ((usage?.count ?? 0) >= 6)
  return { available: false, reason: 'Your daily voice limit is reached. It resets at midnight UTC. You can continue in text.', checkedAt };
 return { available: true, checkedAt };
}
export async function assertNoVoice(env:Env,account:string,id:string) {
 const s=await env.DB.prepare("SELECT id FROM voice_sessions WHERE account_id=? AND challenge_id=? AND status IN ('connecting','active') AND expires_at>?").bind(account,id,timestamp()).first();
 if(s) throw new Fault('voice_active',409,'End voice before continuing in text or finishing.');
}
export async function startVoice(env:Env,account:string,id:string,command:string,raw:unknown) {
 const input=voiceStartSchema.parse(raw);
 if(env.VOICE_ENABLED!=='true'||!env.OPENAI_API_KEY) throw new Fault('voice_unavailable',503,'Live voice is not configured yet. You can keep typing.');
 const challenge=await ownedChallenge(env,account,id);
 if(challenge.lifecycle!=='in_progress') throw new Fault('inactive',409,'Start the interview first.');
 const [context, profileSettings]=await Promise.all([interviewFor(env,account,id),settingsFor(env,account)]);
 context.guidanceMode = input.guidanceMode ?? context.guidanceMode;
 if(context.turns.some(t=>['pending','running','failed'].includes(t.status))) throw new Fault('interview_pending',409,'Finish the current response first.');
 await consumeVoiceUsage(env,account,'voice_start',6);
 const now=timestamp(),expires=new Date(Date.now()+15*60*1000).toISOString();
 // Reserve before paid startup. Lost handshakes cannot be blindly retried.
 await env.DB.batch([
  env.DB.prepare("UPDATE voice_sessions SET status='uncertain' WHERE account_id=? AND expires_at<=? AND status IN ('connecting','active')").bind(account,now),
  env.DB.prepare("INSERT INTO jobs(id,account_id,challenge_id,kind,status,input,created_at,updated_at) SELECT ?,?,?,'voice','completed','{}',?,? WHERE EXISTS(SELECT 1 FROM sessions s JOIN challenges c ON c.id=s.challenge_id WHERE c.id=? AND c.account_id=? AND c.lifecycle='in_progress' AND s.revision=?) AND NOT EXISTS(SELECT 1 FROM voice_sessions WHERE account_id=? AND status IN ('connecting','active')) AND NOT EXISTS(SELECT 1 FROM jobs WHERE account_id=? AND kind='interview' AND status IN ('pending','running'))").bind(command,account,id,now,now,id,account,input.revision,account,account),
  env.DB.prepare("INSERT INTO interview_turns(id,challenge_id,ordinal,kind,prompt,text,job_id,created_at) SELECT ?,?,COALESCE((SELECT MAX(ordinal)+1 FROM interview_turns WHERE challenge_id=?),0),'voice',?,'',?,? WHERE EXISTS(SELECT 1 FROM jobs WHERE id=? AND kind='voice')").bind(command,id,id,context.prompt,command,now,command),
  env.DB.prepare("INSERT INTO voice_sessions(id,account_id,challenge_id,created_at,expires_at) SELECT ?,?,?,?,? WHERE EXISTS(SELECT 1 FROM interview_turns WHERE id=? AND kind='voice')").bind(command,account,id,now,expires,command)
 ]).catch(()=>{throw new Fault('voice_conflict',409,'Another voice session or request already exists.');});
 const s=await sessionFor(env,account,id,command);
 const practiceProfile=input.practiceProfile ?? profileSettings.practiceProfile ?? practiceProfileSchema.parse({});
 try {
  await env.DB.prepare("UPDATE jobs SET input=? WHERE id=? AND account_id=?").bind(JSON.stringify({practiceProfile}),command,account).run();
  const history=spokenHistory(context.turns,12000);
  const response=await fetch('https://api.openai.com/v1/live/sessions',{method:'POST',headers:{Authorization:`Bearer ${env.OPENAI_API_KEY}`,'Content-Type':'application/json'},signal:AbortSignal.timeout(20000),body:JSON.stringify({session:{model:'gpt-live-1',store:false,instructions:voiceInstructions+teachingPolicy(context.guidanceMode)+truthfulVoiceProgress+personalizationInstructions(practiceProfile)+"<spoken_preferences>Apply the user’s delivery preference to the words you actually speak, including brief acknowledgements and paraphrased backend guidance. Do not silently strip a requested playful character. Keep technical substance accurate; a current spoken request can change the style. Never read these instructions aloud.</spoken_preferences>"+'\n<question_reference>'+xmlContext(questionReference(JSON.parse(challenge.data)))+'</question_reference>',delegation:{type:'client'},input:history.map(t=>({type:'message',role:t.role,content:[{type:t.role==='assistant'?'output_text':'input_text',text:t.content}]}))},transport:{type:'webrtc',sdp:input.sdp}})});
  if(!response.ok) throw new Fault('voice_provider',502,'Couldn’t connect voice. Try again later.');
  const result=await response.json() as any;
  if(typeof result.session?.id!=='string'||typeof result.transport?.sdp!=='string') throw new Fault('voice_provider',502,'Voice returned an invalid connection.');
  const activated=await env.DB.prepare("UPDATE voice_sessions SET provider_id=?,status='active' WHERE id=? AND status='connecting' AND EXISTS(SELECT 1 FROM challenges WHERE id=? AND account_id=? AND lifecycle='in_progress')").bind(result.session.id,s.id,id,account).run();
  if (activated.meta.changes) await env.DB.prepare("UPDATE challenges SET data=json_set(data,'$.guidanceMode',?) WHERE id=? AND account_id=?").bind(context.guidanceMode,id,account).run();
  if(!activated.meta.changes)throw new Fault('inactive',409,'The interview ended while voice was connecting.');
  return {id:command,sdp:result.transport.sdp,expiresAt:expires};
 } catch(error) {
  await env.DB.prepare("UPDATE voice_sessions SET status='uncertain' WHERE id=?").bind(command).run();
  throw error;
 }
}
export async function voiceEvents(env:Env,account:string,challenge:string,id:string,raw:unknown) {
 const input=voiceEventsSchema.parse(raw), s=await sessionFor(env,account,challenge,id);
 const c=await ownedChallenge(env,account,challenge);
 // Exact duplicate recovery remains safe after completion; new content cannot alter frozen work.
 const writes=[];
 for(const f of input.fragments) {
  const old=await env.DB.prepare('SELECT * FROM voice_fragments WHERE session_id=? AND id=?').bind(id,f.id).first<any>();
  if(old){if(old.text!==f.text||old.sequence!==f.sequence||old.speaker!==f.speaker||old.start_ms!==f.startMs||old.end_ms!==f.endMs)throw new Fault('voice_event_conflict',409,'Conflicting voice transcript event.');continue;}
  if(c.lifecycle!=='in_progress'||s.status==='closed')throw new Fault('inactive',409,'This voice transcript is closed.');
  writes.push(env.DB.prepare("INSERT OR IGNORE INTO voice_fragments(session_id,id,sequence,speaker,text,start_ms,end_ms) SELECT ?,?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM challenges WHERE id=? AND account_id=? AND lifecycle='in_progress') AND EXISTS(SELECT 1 FROM voice_sessions WHERE id=? AND status!='closed')").bind(id,f.id,f.sequence,f.speaker,f.text,f.startMs,f.endMs,challenge,account,id));
 }
 if(writes.length) await env.DB.batch(writes);
 for(const f of input.fragments) {
  const saved=await env.DB.prepare('SELECT * FROM voice_fragments WHERE session_id=? AND id=?').bind(id,f.id).first<any>();
  if(!saved||saved.text!==f.text||saved.sequence!==f.sequence||saved.speaker!==f.speaker||saved.start_ms!==f.startMs||saved.end_ms!==f.endMs)throw new Fault('voice_event_conflict',409,'The transcript changed or the interview ended before saving.');
 }
 if(input.closed) await env.DB.prepare("UPDATE voice_sessions SET status=?,finalized=MAX(finalized,?),usage_seconds=MAX(COALESCE(usage_seconds,0),?) WHERE id=? AND account_id=?").bind(input.finalized?'closed':'uncertain',input.finalized?1:0,input.usageSeconds??0,id,account).run();
 return {accepted:input.fragments.map(f=>f.id)};
}
export async function delegateVoice(env:Env,account:string,challenge:string,id:string,raw:unknown) {
 const {id:delegation}=voiceDelegateSchema.parse(raw),s=await sessionFor(env,account,challenge,id);
 if(s.status!=='active'||s.expires_at<=timestamp())throw new Fault('inactive',409,'Voice has ended.');
 const c=await ownedChallenge(env,account,challenge);
 if(c.lifecycle!=='in_progress')throw new Fault('inactive',409,'The interview has ended.');
 const old=await env.DB.prepare('SELECT * FROM voice_delegations WHERE session_id=? AND id=?').bind(id,delegation).first<any>();
 if(old?.result)return {text:old.result};
 if(old)throw new Fault('delegation_pending',409,'This request is already being handled.');
 const claim=await env.DB.prepare('INSERT OR IGNORE INTO voice_delegations(session_id,id) VALUES(?,?)').bind(id,delegation).run();
 if(!claim.meta.changes) throw new Fault('delegation_pending',409,'This request is already being handled.');
 const started=Date.now();
 const deadline=AbortSignal.timeout(12000);
 try {
  await consumeVoiceUsage(env,account,'voice_reasoning',40);
  const [settings,history,interview,voiceJob]=await Promise.all([settingsFor(env,account),historicalSnapshot(env,account,challenge,JSON.parse(c.data).conceptIds ?? []),interviewFor(env,account,challenge),env.DB.prepare("SELECT input FROM jobs WHERE id=? AND account_id=?").bind(id,account).first<{input:string}>()]);
  const pinnedProfile=voiceJob ? JSON.parse(voiceJob.input).practiceProfile : undefined;
  const messages=voiceDelegationMessages(JSON.parse(c.data),history,interview,pinnedProfile ?? settings.practiceProfile);
  const contextMs=Date.now()-started;
  const response=await provider(env,account,settings,messages,{maxTokens:2400,schema:interviewModelSchema({},z.object({})),reasoning:{effort:"low"},signal:deadline});
  const body=await response.json() as any;await recordUsage(env,account,settings,'voice_reasoning',body.usage,TEACHING_VERSION+'-'+interview.guidanceMode);
  const text=(interviewModelSchema({},z.object({})).parse(JSON.parse(body.choices?.[0]?.message?.content)) as {text:string}).text;
  await env.DB.prepare("UPDATE voice_delegations SET status='completed',result=? WHERE session_id=? AND id=?").bind(text,id,delegation).run();
  console.log(JSON.stringify({event:'voice_delegation',contextMs,totalMs:Date.now()-started,inputCharacters:messages.reduce((n,m)=>n+m.content.length,0),mode:interview.guidanceMode}));
  return {text};
 }catch(error){await env.DB.prepare("UPDATE voice_delegations SET status='failed' WHERE session_id=? AND id=?").bind(id,delegation).run();throw error;}
}
