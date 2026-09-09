import { randomBytes, createHash } from "node:crypto";
import { writeFileSync, mkdirSync } from "node:fs";
const code = randomBytes(24).toString("base64url");
const digest = createHash("sha256").update(code).digest("hex");
mkdirSync(".local", { recursive: true, mode: 0o700 });
const file = ".local/invite-" + Date.now() + ".txt";
writeFileSync(file, code + "\n", { mode: 0o600 });
console.log(
  `Invite saved to ${file}. Execute this SQL in the intended D1 database:`,
);
console.log(
  `INSERT INTO invites(hash,created_at) VALUES('${digest}','${new Date().toISOString()}');`,
);
