import { questionProjection, type Question } from "./library";
import { Fault, timestamp } from "./domain";
import { detail, settingsFor } from "./store";
import type { Env } from "./platform";
/** Stable creation watermark; paginated to bound D1 work and response size. */
export async function exportPage(env: Env, account: string, cursor?: string) {
  let at = timestamp(), after = "", afterID = "", questionAfter = "", questionID = "";
  if (cursor) {
    try {
      const value = JSON.parse(atob(cursor));
      if (![value.at,value.after,value.id].every(x => typeof x === "string")
        || !Number.isFinite(Date.parse(value.at))) throw Error();
      at = value.at; after = value.after; afterID = value.id;
      questionAfter = value.questionAfter ?? ""; questionID = value.questionID ?? "";
      if (typeof questionAfter !== "string" || typeof questionID !== "string") throw Error();
    } catch { throw new Fault("invalid_cursor",400,"Invalid export cursor."); }
  }
  const rows = await env.DB.prepare(`SELECT id,created_at FROM challenges WHERE account_id=?
    AND created_at<=? AND (created_at>? OR (created_at=? AND id>?))
    ORDER BY created_at,id LIMIT 11`).bind(account,at,after,after,afterID)
    .all<{id:string;created_at:string}>();
  const questions = await env.DB.prepare(`SELECT * FROM questions WHERE account_id=?
    AND created_at<=? AND (created_at>? OR (created_at=? AND id>?))
    ORDER BY created_at,id LIMIT 11`).bind(account,at,questionAfter,questionAfter,questionID).all<Question>();
  const questionPage = questions.results.slice(0,10), lastQuestion = questionPage.at(-1);
  const page = rows.results.slice(0,10), last=page.at(-1);
  const sessions=[];
  for (const row of page) sessions.push(await detail(env,account,row.id));
  return {version:1,asOf:at,settings:await settingsFor(env,account),sessions,questions:questionPage.map(questionProjection),
    nextCursor:rows.results.length>10 || questions.results.length>10 ? btoa(JSON.stringify({at,after:last?.created_at ?? after,id:last?.id ?? afterID,questionAfter:lastQuestion?.created_at ?? questionAfter,questionID:lastQuestion?.id ?? questionID})) : null};
}
