/**
 * Downloads new voice notes (Settings → Feedback) as .m4a files into .local/voice-notes/, newest last.
 * File names carry the date, length and note id, never the account. Already-downloaded notes are skipped.
 *
 *   bun scripts/voice-notes.ts                 # production
 *   bun scripts/voice-notes.ts --development   # development D1
 *
 * Needs wrangler logged in to the Cloudflare account. The recordings are user data: keep them on this machine.
 */
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const development = process.argv.includes("--development");
const root = join(import.meta.dir, "..");
const folder = join(root, ".local", "voice-notes", development ? "development" : "production");
mkdirSync(folder, { recursive: true });
const have = new Set(readdirSync(folder).map(name => name.match(/-([0-9a-f-]{36})\.m4a$/)?.[1]).filter(Boolean));

function query(sql: string) {
  const args = ["wrangler", "d1", "execute", development ? "drillbit-development" : "drillbit-production", "--remote", "--json", "--command", sql];
  if (!development) args.push("--env", "production");
  const out = execFileSync(join(root, "apps/api/node_modules/.bin/" + args[0]), args.slice(1), { cwd: join(root, "apps/api"), encoding: "utf8", maxBuffer: 256 * 1024 * 1024 });
  return JSON.parse(out)[0].results as Record<string, string | number>[];
}

// One note per query keeps each response small however long the recordings are.
const list = query("SELECT id,created_at,duration_seconds,app_version FROM voice_notes ORDER BY created_at");
const fresh = list.filter(note => !have.has(String(note.id)));
for (const note of fresh) {
  const id = String(note.id);
  if (!/^[0-9a-f-]{36}$/i.test(id)) continue;
  const [row] = query(`SELECT hex(audio) AS audio FROM voice_notes WHERE id='${id}'`);
  const stamp = String(note.created_at).slice(0, 16).replace(/[:T]/g, "-");
  const name = `${stamp}-${Math.round(Number(note.duration_seconds))}s-${id}.m4a`;
  writeFileSync(join(folder, name), Buffer.from(String(row.audio), "hex"));
  console.log(`${name}${note.app_version ? `  (app ${note.app_version})` : ""}`);
}
console.log(`${fresh.length} new, ${list.length} in total. Folder: ${folder}${existsSync(folder) && fresh.length ? "\nOpen it with: open " + JSON.stringify(folder) : ""}`);
