import { visibleQuestion } from "../context";
import { messagesFor, type ModelMessage } from '../ai';

/** Provider fragments are transport records, not conversational turns. Never send
 * their IDs/timestamps or repeat the question inside every exchange. */
export function spokenHistory(turns: any[], budget = 16000): ModelMessage[] {
  const messages: ModelMessage[] = [];
  const append = (role: 'user' | 'assistant', text: string) => {
    if (!text) return;
    const last = messages.at(-1);
    if (last?.role === role) last.content += text;
    else messages.push({role, content:text});
  };
  for (const turn of turns) {
    if (turn.kind === 'voice') {
      // Match the native transcript projection: brief overlapping backchannels
      // must not split a user's sentence into separate model requests.
      const rows: {speaker:'user'|'assistant';text:string;endMs:number}[] = [];
      const latest = new Map<string,number>();
      for (const fragment of [...(turn.voice ?? [])].sort((a,b)=>(a.sequence ?? 0)-(b.sequence ?? 0))) {
        const speaker = fragment.speaker === 'user' ? 'user' : 'assistant';
        const index = latest.get(speaker);
        if (index !== undefined && fragment.startMs >= rows[index].endMs && fragment.startMs - rows[index].endMs <= 1500) {
          rows[index].text += fragment.text;
          rows[index].endMs = fragment.endMs;
        } else {
          latest.set(speaker,rows.length);
          rows.push({speaker,text:fragment.text,endMs:fragment.endMs});
        }
      }
      for (const row of rows) append(row.speaker,row.text);
    } else {
      append('user', turn.text || (turn.result ? `[Requested ${turn.kind}]` : ''));
      if (turn.result) append('assistant', turn.result.text);
    }
  }
  // Keep the most recent conversation, mark omissions; persistence stays complete.
  let remaining = budget;
  const kept: ModelMessage[] = [];
  for (const message of [...messages].reverse()) {
    if (remaining <= 0) break;
    const content = message.content.length > remaining ? '[Earlier part omitted] ' + message.content.slice(-Math.max(0, remaining - 24)) : message.content;
    kept.unshift({...message, content}); remaining -= content.length;
  }
  return kept;
}
export function questionReference(question: any) {
  return visibleQuestion(question);
}
export function voiceDelegationMessages(question: any, history: unknown, interview: any, practiceProfile?: unknown): ModelMessage[] {
  const dialogue = spokenHistory(interview.turns);
  const latestUser = dialogue.map(m => m.role).lastIndexOf('user');
  const messages = messagesFor('interview', {
    practiceProfile, question: questionReference(question), historicalSnapshot: history,
    interview: {guidanceMode:interview.guidanceMode, turns:[{kind:'voice',voice:dialogue.slice(0, Math.max(0, latestUser)).map(m=>({speaker:m.role,text:m.content}))}]},
    action:{kind:'answer',text:latestUser >= 0 ? dialogue[latestUser].content : '[No spoken request yet. Invite me to begin briefly.]'},
  });
  messages[0].content += `
<spoken_delivery>The same JSON response contract applies. The text will be spoken aloud: one short conversational paragraph, normally two or three sentences. Do not write Markdown, bullet lists, a JSON example inside text, or code fences. Describe example fields in ordinary words. Only say path syntax when the user asks for it. Keep any explanation under 120 words. Older assistant fragments may have been interrupted; never assume they were heard. If the user complains about waiting, acknowledge the wait without denying their experience, inventing a cause or asking them to wait again.</spoken_delivery>`;
  return messages;
}
