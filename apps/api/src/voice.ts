import { z } from 'zod';
import { interviewModelSchema, parseModelJSON, provider, recordUsage } from './ai';
import { xmlContext } from './context';
import { Fault, practiceProfileSchema, timestamp } from './domain';
import { historicalSnapshot } from './history';
import { guidedPathFor, interviewFor, mockRound } from './interview';
import { consumeUsage, type Env } from './platform';
import { limits, nextUtcMidnight, planFor } from './plans';
import { practicePersonality, questionTerminology } from "./prompts/interviewer";
import { personalizationInstructions } from "./prompts/personalization";
import { guidanceModeSchema, TEACHING_VERSION, teachingPolicy, truthfulVoiceProgress } from "./prompts/teaching";
import { questionReference, spokenHistory, voiceDelegationMessages } from "./prompts/voice-context";
import { ownedChallenge, settingsFor } from './store';

export const voiceStartSchema = z.object({practiceProfile:practiceProfileSchema.optional(),guidanceMode:guidanceModeSchema.optional(),sdp:z.string().min(1).max(64000),revision:z.number().int().nonnegative()});
export const voiceFragmentSchema = z.object({id:z.string().min(1).max(160),sequence:z.number().int().nonnegative().max(5999),speaker:z.enum(['user','assistant']),text:z.string().max(8000),startMs:z.number().int().nonnegative(),endMs:z.number().int().nonnegative()}).refine(x=>x.endMs>=x.startMs);
export const voiceEventsSchema = z.object({fragments:z.array(voiceFragmentSchema).max(100),closed:z.boolean().optional(),finalized:z.boolean().optional(),usageSeconds:z.number().nonnegative().max(86400).optional()});
export const voiceDelegateSchema = z.object({id:z.string().min(1).max(160)});
export const voiceInstructions = `${questionTerminology}
${practicePersonality}
<interview>Discuss only visible requirements. Do not invent evaluation criteria. Delegate substantive technical feedback, corrections, examples and hints to the backend. Use its guidance naturally, briefly, then listen. Never narrate delegation: no \"let me check\", \"I'll see if\", \"one moment\" or any hint that something is being looked up. Respond to what they said in one short sentence, and only after backend guidance arrives bring in its substance as your own thought. Backend guidance is always words to say, never a status; if it is only a short nudge, say it and ask your one next question. Never tell them that advice, guidance or a response did not come through, and never offer to continue in text; the app handles that. Don't read XML. Do not claim to save, finish or change the exercise; the app owns those actions. Typed drafts are separate from speech. Conversation history may include interrupted or unheard assistant words; don't assume they were heard.</interview>
<pace>They are thinking out loud under pressure. A pause, an \"um\", a trailing sentence or a half-formed idea is not your turn: stay quiet and let them finish. Only reply once they have clearly landed a point or asked you something. When they are stuck in silence for a long while, one short nudge is enough.</pace>`;
// The live model only hears the roadmap at session start; later movement arrives inside the delegated guidance.
function spokenGuidedPath(path?: {steps:string[]; current:number}) {
 if(!path) return '';
 const steps=path.steps.map((step,index)=>`${index+1}. ${step}${index===path.current?' (current)':''}`).join('; ');
 return `<guidedPath>The learner sees this roadmap on screen: ${steps}. Steer toward the current step and bring them back to it when they drift; when the backend's guidance moves on to the next step, follow it and name the step in plain words.</guidedPath>`;
}
async function sessionFor(env:Env, account:string, challenge:string, id:string) {
 await ownedChallenge(env,account,challenge);
 const s=await env.DB.prepare('SELECT * FROM voice_sessions WHERE id=? AND account_id=? AND challenge_id=?').bind(id,account,challenge).first<any>();
 if(!s) throw new Fault('not_found',404,'Voice session not found.');
 return s;
}
// A start that never produced a provider session costs nothing, so it doesn't count.
async function refundVoiceStart(env: Env, account: string, day: string) {
 await env.DB.prepare("UPDATE usage SET count=count-1 WHERE account_id=? AND day=? AND kind='voice_start' AND count>0").bind(account, day).run();
}
const weekday = (iso: string) => new Date(iso).toLocaleDateString('en-US', { weekday: 'long', timeZone: 'UTC' });
/**
 * What this account may do with voice right now. Free: the first few sessions, then one taste every
 * `voiceTasteDays`. Pro: a daily fair-use cap that is never shown. Both carry the session cap in seconds.
 */
export async function voiceCapability(env: Env, account: string) {
 const checkedAt = timestamp();
 if (env.VOICE_ENABLED !== 'true' || !env.OPENAI_API_KEY)
  return { available: false, reason: 'Live voice is currently unavailable. You can continue in text.', checkedAt };
 const plan = await planFor(env, account), caps = limits(env, plan);
 const sessionSeconds = caps.voiceSessionSeconds;
 // `plan` on the capability tells the start handler whether a refusal is a paywall or a fair-use pause.
 const today = await env.DB.prepare("SELECT count FROM usage WHERE account_id=? AND day=? AND kind='voice_start'").bind(account, checkedAt.slice(0,10)).first<{count:number}>();
 if (plan === 'pro') {
  if ((today?.count ?? 0) >= caps.voiceStartsPerDay)
   return { available: false, plan, reason: 'That’s a lot of talking for one day. Voice is back tomorrow.', checkedAt, sessionSeconds, resetsAt: nextUtcMidnight(checkedAt) };
  return { available: true, plan, checkedAt, sessionSeconds };
 }
 // Sessions that reached the provider; refunded starts never activate and waived ones never heard the user.
 const history = await env.DB.prepare("SELECT COUNT(*) n, MAX(created_at) last FROM voice_sessions WHERE account_id=? AND provider_id IS NOT NULL AND waived=0").bind(account).first<{n:number; last:string|null}>();
 const used = history?.n ?? 0;
 if (used < caps.voiceFreeLifetime) {
  const remaining = caps.voiceFreeLifetime - used;
  return { available: true, plan, checkedAt, sessionSeconds, remaining, limit: caps.voiceFreeLifetime, kind: 'intro' as const };
 }
 const nextAt = history?.last ? new Date(Date.parse(history.last) + caps.voiceTasteDays * 86_400_000).toISOString() : checkedAt;
 if (nextAt > checkedAt)
  return { available: false, plan, reason: `Your next free voice session comes back ${weekday(nextAt)}. Pro has it any time.`, checkedAt, sessionSeconds, remaining: 0, limit: 1, resetsAt: nextAt, kind: 'taste' as const };
 return { available: true, plan, checkedAt, sessionSeconds, remaining: 1, limit: 1, kind: 'taste' as const };
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
 const day=timestamp().slice(0,10);
 const capability=await voiceCapability(env,account);
 if(!capability.available || !capability.plan) throw capability.plan === 'free' ? new Fault('voice_gate',402,capability.reason ?? 'Voice isn’t available right now.') : new Fault('usage_limit',429,capability.reason ?? 'Voice isn’t available right now.');
 const plan=capability.plan, caps=limits(env,plan);
 await consumeUsage(env,account,'voice_start',caps.voiceStartsPerDay);
 // The session cap plus a little slack for the close handshake; events after this are refused.
 const sessionSeconds=caps.voiceSessionSeconds;
 const now=timestamp(),expires=new Date(Date.now()+(sessionSeconds+30)*1000).toISOString();
 // Reserve before paid startup. Lost handshakes cannot be blindly retried.
 const s=await env.DB.batch([
  env.DB.prepare("UPDATE voice_sessions SET status='uncertain' WHERE account_id=? AND expires_at<=? AND status IN ('connecting','active')").bind(account,now),
  env.DB.prepare("INSERT INTO jobs(id,account_id,challenge_id,kind,status,input,created_at,updated_at) SELECT ?,?,?,'voice','completed','{}',?,? WHERE EXISTS(SELECT 1 FROM sessions s JOIN challenges c ON c.id=s.challenge_id WHERE c.id=? AND c.account_id=? AND c.lifecycle='in_progress' AND s.revision=?) AND NOT EXISTS(SELECT 1 FROM voice_sessions WHERE account_id=? AND status IN ('connecting','active')) AND NOT EXISTS(SELECT 1 FROM jobs WHERE account_id=? AND kind='interview' AND status IN ('pending','running'))").bind(command,account,id,now,now,id,account,input.revision,account,account),
  env.DB.prepare("INSERT INTO interview_turns(id,challenge_id,ordinal,kind,prompt,text,job_id,created_at) SELECT ?,?,COALESCE((SELECT MAX(ordinal)+1 FROM interview_turns WHERE challenge_id=?),0),'voice',?,'',?,? WHERE EXISTS(SELECT 1 FROM jobs WHERE id=? AND kind='voice')").bind(command,id,id,context.prompt,command,now,command),
  env.DB.prepare("INSERT INTO voice_sessions(id,account_id,challenge_id,created_at,expires_at) SELECT ?,?,?,?,? WHERE EXISTS(SELECT 1 FROM interview_turns WHERE id=? AND kind='voice')").bind(command,account,id,now,expires,command)
 ]).catch(()=>{throw new Fault('voice_conflict',409,'Another voice session or request already exists.');})
  .then(()=>sessionFor(env,account,id,command))
  .catch(async error=>{await refundVoiceStart(env,account,day); throw error;});
 const practiceProfile=input.practiceProfile ?? profileSettings.practiceProfile ?? practiceProfileSchema.parse({});
 let providerSession=false;
 try {
  await env.DB.prepare("UPDATE jobs SET input=? WHERE id=? AND account_id=?").bind(JSON.stringify({practiceProfile}),command,account).run();
  const history=spokenHistory(context.turns,12000);
  const guidedPath=guidedPathFor(JSON.parse(challenge.data),context.guidanceMode,context.turns);
  const response=await fetch('https://api.openai.com/v1/live/sessions',{method:'POST',headers:{Authorization:`Bearer ${env.OPENAI_API_KEY}`,'Content-Type':'application/json'},signal:AbortSignal.timeout(20000),body:JSON.stringify({session:{model:'gpt-live-1',store:false,instructions:voiceInstructions+teachingPolicy(context.guidanceMode)+spokenGuidedPath(guidedPath)+truthfulVoiceProgress+personalizationInstructions(practiceProfile)+"<spoken_preferences>Apply the user’s delivery preference to the words you actually speak, including brief acknowledgements and paraphrased backend guidance. Do not silently strip a requested playful character. Keep technical substance accurate; a current spoken request can change the style. Never read these instructions aloud.</spoken_preferences>"+'\n<question_reference>'+xmlContext(questionReference(JSON.parse(challenge.data)))+'</question_reference>',delegation:{type:'client'},input:history.map(t=>({type:'message',role:t.role,content:[{type:t.role==='assistant'?'output_text':'input_text',text:t.content}]}))},transport:{type:'webrtc',sdp:input.sdp}})});
  if(!response.ok) {
   // The provider's reason is the only way to see a rejected session shape; it never contains practice content.
   const detail=await response.text().catch(()=>'' );
   console.log(JSON.stringify({event:'voice_provider_rejected',status:response.status,detail:detail.slice(0,400)}));
   throw new Fault('voice_provider',502,'Couldn’t connect voice. Try again later.');
  }
  const result=await response.json() as any;
  if(typeof result.session?.id!=='string'||typeof result.transport?.sdp!=='string') throw new Fault('voice_provider',502,'Voice returned an invalid connection.');
  providerSession=true;
  const activated=await env.DB.prepare("UPDATE voice_sessions SET provider_id=?,status='active' WHERE id=? AND status='connecting' AND EXISTS(SELECT 1 FROM challenges WHERE id=? AND account_id=? AND lifecycle='in_progress')").bind(result.session.id,s.id,id,account).run();
  if (activated.meta.changes) await env.DB.prepare("UPDATE challenges SET data=json_set(data,'$.guidanceMode',?) WHERE id=? AND account_id=?").bind(context.guidanceMode,id,account).run();
  if(!activated.meta.changes)throw new Fault('inactive',409,'The interview ended while voice was connecting.');
  return {id:command,sdp:result.transport.sdp,expiresAt:expires,sessionSeconds};
 } catch(error) {
  await env.DB.prepare("UPDATE voice_sessions SET status='uncertain' WHERE id=?").bind(command).run();
  if(!providerSession) await refundVoiceStart(env,account,day);
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
 // A confirmed close before the user said a word is a free look: it gives the start back, so switching between voice
 // and text costs nothing. Unconfirmed closes still count, since more speech could yet arrive.
 if(input.closed&&input.finalized){
  const waived=await env.DB.prepare("UPDATE voice_sessions SET waived=1 WHERE id=? AND account_id=? AND waived=0 AND status='closed' AND provider_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM voice_fragments WHERE session_id=? AND speaker='user')").bind(id,account,id).run();
  if(waived.meta.changes) await refundVoiceStart(env,account,String(s.created_at).slice(0,10));
 }
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
  await consumeUsage(env,account,'voice_reasoning',limits(env,await planFor(env,account)).voiceReasoningPerDay);
  const [settings,history,interview,voiceJob]=await Promise.all([settingsFor(env,account),historicalSnapshot(env,account,challenge,JSON.parse(c.data).conceptIds ?? []),interviewFor(env,account,challenge),env.DB.prepare("SELECT input FROM jobs WHERE id=? AND account_id=?").bind(id,account).first<{input:string}>()]);
  const pinnedProfile=voiceJob ? JSON.parse(voiceJob.input).practiceProfile : undefined;
  const data=JSON.parse(c.data);
  const timing=interview.guidanceMode==='mock_interview'?mockRound(data,c.created_at,interview.turns):undefined;
  const guidedPath=guidedPathFor(data,interview.guidanceMode,interview.turns);
  const messages=voiceDelegationMessages(data,history,{...interview,timing,guidedPath},pinnedProfile ?? settings.practiceProfile);
  const contextMs=Date.now()-started;
  // The pinned spoken contract predates roadmap steps; guided sessions read the step alongside it.
  const spoken=interviewModelSchema({promptVersion:"interviewer-teaching-v3"},z.object({}));
  const voiceSchema=guidedPath ? spoken.and(z.object({step:z.number().int().min(0).max(4).optional()})) : spoken;
  // About one delegation in fifty comes back as a whitespace runaway cut off by max_tokens; one more try fits inside the deadline.
  let text='',step:number|undefined;
  for(let attempt=0;;attempt++){
   const response=await provider(env,account,settings,messages,{kind:'voice_reasoning',maxTokens:900,schema:voiceSchema,reasoning:{enabled:false},signal:deadline});
   const body=await response.json() as any;await recordUsage(env,account,settings,'voice_reasoning',body.usage,TEACHING_VERSION+'-'+interview.guidanceMode);
   try { const parsed=voiceSchema.parse(parseModelJSON(body.choices?.[0]?.message?.content)) as {text:string;step?:number}; text=parsed.text; step=parsed.step; break; }
   catch(error){ if(attempt>0 || Date.now()-started>6000) throw error; console.log(JSON.stringify({event:'voice_delegation_retry',finishReason:body.choices?.[0]?.finish_reason})); }
  }
  // Voice has no answer turn to carry the step, so the challenge remembers how far the roadmap got.
  const reached=guidedPath && typeof step==='number' ? Math.min(step,guidedPath.steps.length-1) : undefined;
  const writes=[env.DB.prepare("UPDATE voice_delegations SET status='completed',result=? WHERE session_id=? AND id=?").bind(text,id,delegation)];
  if(reached!==undefined && reached>guidedPath!.current) writes.push(env.DB.prepare("UPDATE challenges SET data=json_set(data,'$.guidedStep',?) WHERE id=? AND account_id=?").bind(reached,challenge,account));
  await env.DB.batch(writes);
  console.log(JSON.stringify({event:'voice_delegation',contextMs,totalMs:Date.now()-started,inputCharacters:messages.reduce((n,m)=>n+m.content.length,0),mode:interview.guidanceMode}));
  return reached!==undefined ? {text,step:Math.max(reached,guidedPath!.current)} : {text};
 }catch(error){await env.DB.prepare("UPDATE voice_delegations SET status='failed' WHERE session_id=? AND id=?").bind(id,delegation).run();throw error;}
}
