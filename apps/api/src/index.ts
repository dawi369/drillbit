import { updateContext, receive } from "./companion";
import { Hono } from "hono";
import { bodyLimit } from "hono/body-limit";
import { streamSSE } from "hono/streaming";
import { z } from "zod";
import {
  Fault,
  generationSchema,
  levelForDifficulty,
  answerSchema,
  settingsSchema,
  requireCommand,
  timestamp,
  uuid,
  nextDaily,
  parseJSON,
} from "./domain";
import { identity, hash, encrypt, consumeUsage, type Env } from "./platform";
import {
  accountFor,
  settingsFor,
  activeChallenge,
  ownedChallenge,
  detail,
  present,
  createJob,
  complete,
  dispatch,
  type Account,
  type ChallengeRow,
  type Job,
} from "./store";
import { messagesFor, provider, textDeltas, recordUsage } from "./ai";
import { requestHelp, adopt } from "./practice";
import { reconcile } from "./jobs";
export { PracticeWorkflow } from "./jobs";
export const app = new Hono<{
  Bindings: Env;
  Variables: { account: Account; requestId: string };
}>();
app.use(
  "*",
  bodyLimit({
    maxSize: 128 * 1024,
    onError: (c) =>
      c.json(
        {
          error: {
            code: "request_too_large",
            message: "Keep your answer under 24,000 characters.",
          },
        },
        413,
      ),
  }),
);
app.use("*", async (c, next) => {
  c.set("requestId", uuid());
  await next();
  c.header("X-Request-ID", c.get("requestId"));
  c.header("Cache-Control", "no-store");
});
app.onError((error, c) => {
  const fault =
    error instanceof Fault
      ? error
      : error instanceof z.ZodError
        ? new Fault("invalid_input", 400, "Check the supplied fields.")
        : new Fault(
            "internal",
            500,
            "Something went wrong. Your saved answer is safe.",
          );
  if (fault.status >= 500)
    console.error(
      JSON.stringify({
        event: "request_failed",
        requestId: c.get("requestId"),
        code: fault.code,
      }),
    );
  return c.json(
    {
      error: {
        code: fault.code,
        message: fault.message,
        retryable: fault.status >= 500,
        requestId: c.get("requestId"),
      },
    },
    fault.status as 400,
  );
});
app.get("/health", (c) => c.json({ status: "ok" }));
app.get("/v1/widget", async (c) => {
  const token = c.req.header("Authorization")?.replace(/^Bearer /, "");
  if (!token)
    throw new Fault("unauthenticated", 401, "Open Drillbit to refresh.");
  const device = await c.env.DB.prepare(
    "SELECT d.account_id FROM devices d JOIN accounts a ON a.id=d.account_id WHERE d.token_hash=? AND d.expires_at>? AND a.status='active'",
  )
    .bind(await hash(token), timestamp())
    .first<{ account_id: string }>();
  if (!device)
    throw new Fault("unauthenticated", 401, "Open Drillbit to refresh.");
  await c.env.DB.prepare("UPDATE accounts SET last_seen=? WHERE id=?")
    .bind(timestamp(), device.account_id)
    .run();
  const active = await activeChallenge(c.env, device.account_id);
  return c.json({
    challenge: active ? present(active) : null,
    updatedAt: timestamp(),
  });
});
app.use("/v1/*", async (c, next) => {
  const subject = await identity(c.env, c.req.header("Authorization"));
  const account = await accountFor(c.env, subject);
  c.set("account", account);
  const permitted = ["/v1/bootstrap", "/v1/invite", "/v1/account"];
  if (account.status !== "active" && !permitted.includes(c.req.path))
    throw new Fault(
      "invite_required",
      403,
      "Redeem an invite to start practicing.",
    );
  await next();
});
app.get("/v1/bootstrap", async (c) => {
  const a = c.get("account");
  const active = await activeChallenge(c.env, a.id);
  const jobs = await c.env.DB.prepare(
    "SELECT id,kind,status,error,challenge_id FROM jobs WHERE account_id=? AND status IN ('pending','running','failed') ORDER BY created_at DESC LIMIT 20",
  )
    .bind(a.id)
    .all();
  const credential = await c.env.DB.prepare(
    "SELECT suffix FROM credentials WHERE account_id=?",
  )
    .bind(a.id)
    .first();
  return c.json({
    account: { id: a.id, status: a.status },
    settings: await settingsFor(c.env, a.id),
    challenge: active ? await detail(c.env, a.id, active.id) : null,
    jobs: jobs.results,
    credential,
    capabilities: {
      managedAI: c.env.MANAGED_AI_ENABLED === "true",
      voiceInterview: false,
      automaticCompanion: c.env.COMPANION_AUTO_ENABLED === "true",
    },
  });
});
app.post("/v1/invite", async (c) => {
  const { code } = z
    .object({ code: z.string().min(8).max(200) })
    .parse(await c.req.json());
  const account = c.get("account");
  const digest = await hash(code.trim());
  await c.env.DB.batch([
    c.env.DB.prepare(
      "UPDATE invites SET redeemed_by=? WHERE hash=? AND (redeemed_by IS NULL OR redeemed_by=?)",
    ).bind(account.id, digest, account.id),
    c.env.DB.prepare(
      "UPDATE accounts SET status='active' WHERE id=? AND EXISTS(SELECT 1 FROM invites WHERE hash=? AND redeemed_by=?)",
    ).bind(account.id, digest, account.id),
  ]);
  const result = await c.env.DB.prepare(
    "SELECT status FROM accounts WHERE id=?",
  )
    .bind(account.id)
    .first<{ status: string }>();
  if (result?.status !== "active")
    throw new Fault(
      "invalid_invite",
      422,
      "That invite is invalid or has already been used.",
    );
  return c.json({ ok: true });
});
app.put("/v1/settings", async (c) => {
  const settings = settingsSchema.parse(await c.req.json());
  const account = c.get("account").id;
  settings.engineeringLevel ??= (await settingsFor(c.env, account)).engineeringLevel;
  if (
    JSON.stringify(settings) ===
    JSON.stringify(await settingsFor(c.env, account))
  )
    return c.json(settings);
  if (
    settings.aiMode === "byok" &&
    !(await c.env.DB.prepare("SELECT id FROM credentials WHERE account_id=?")
      .bind(account)
      .first())
  )
    throw new Fault(
      "credential_required",
      422,
      "Add your OpenRouter key first.",
    );
  await c.env.DB.batch([
    c.env.DB.prepare(
      "UPDATE settings SET data=?,next_due=? WHERE account_id=?",
    ).bind(JSON.stringify(settings), nextDaily(settings), account),
    c.env.DB.prepare(
      "UPDATE challenges SET lifecycle='expired' WHERE account_id=? AND lifecycle='prepared'",
    ).bind(account),
    c.env.DB.prepare(
      "UPDATE jobs SET status='cancelled' WHERE account_id=? AND kind='generate' AND status IN ('pending','running')",
    ).bind(account),
  ]);
  return c.json(settings);
});
app.post("/v1/challenges", async (c) => {
  const a = c.get("account").id,
    id = requireCommand(c.req.header("Idempotency-Key"));
  const existing = await c.env.DB.prepare(
    "SELECT * FROM jobs WHERE id=? AND account_id=?",
  )
    .bind(id, a)
    .first();
  if (existing) return c.json(existing);
  const rawPreparation = await c.req.text();
  let preparationInput: unknown = {};
  try {
    if (rawPreparation) preparationInput = JSON.parse(rawPreparation);
  } catch {
    throw new Fault("invalid_input", 400, "Preparation must be valid JSON.");
  }
  const preparation = generationSchema.parse(preparationInput);
  const active = await activeChallenge(c.env, a);
  if (
    preparation.replaceId &&
    (active?.id !== preparation.replaceId || active.lifecycle !== "ready")
  )
    throw new Fault(
      "session_started",
      409,
      "Your current draft will stay open. Finish or skip it before preparing another.",
    );
  if (active && !preparation.replaceId)
    return c.json({ challenge: await detail(c.env, a, active.id) });
  const pending = await c.env.DB.prepare(
    "SELECT * FROM jobs WHERE account_id=? AND kind='generate' AND status IN ('pending','running') LIMIT 1",
  )
    .bind(a)
    .first();
  if (pending) return c.json(pending);
  let followUp: unknown;
  if (preparation.followUpId) {
    const previous = await detail(c.env, a, preparation.followUpId);
    if (previous.lifecycle !== "completed")
      throw new Fault(
        "invalid_follow_up",
        409,
        "Finish the previous practice first.",
      );
    followUp = {
      question: present(await ownedChallenge(c.env, a, preparation.followUpId)),
      reflection: previous.reflection,
      assistance: previous.help.map((h) => ({
        kind: h.kind,
        status: h.status,
      })),
      adoptions: previous.adoptions,
    };
  }
  await consumeUsage(c.env, a, "generate", 10);
  return c.json(
    await createJob(c.env, a, id, "generate", null, {
      ...preparation,
      followUp,
      settings: {
        ...(await settingsFor(c.env, a)),
        ...(preparation.focus ? { focus: preparation.focus } : {}),
        ...(preparation.difficulty
          ? { difficulty: preparation.difficulty }
          : {}),
        ...(preparation.engineeringLevel ? { engineeringLevel: preparation.engineeringLevel } : preparation.difficulty ? { engineeringLevel: levelForDifficulty(preparation.difficulty) } : {}),
      },
    }),
    202,
  );
});
app.put("/v1/challenges/:id/companion", async (c) =>
  c.json(
    await updateContext(
      c.env,
      c.get("account").id,
      c.req.param("id"),
      requireCommand(c.req.header("Idempotency-Key")),
      await c.req.json(),
    ),
  ),
);
app.post("/v1/challenges/:id/deliveries", async (c) =>
  c.json(
    await receive(
      c.env,
      c.get("account").id,
      c.req.param("id"),
      await c.req.json(),
    ),
  ),
);
app.post("/v1/challenges/:id/help", async (c) =>
  c.json(
    await requestHelp(
      c.env,
      c.get("account").id,
      c.req.param("id"),
      requireCommand(c.req.header("Idempotency-Key")),
      await c.req.json(),
    ),
    202,
  ),
);
app.post("/v1/challenges/:id/adopt", async (c) =>
  c.json(
    await adopt(
      c.env,
      c.get("account").id,
      c.req.param("id"),
      requireCommand(c.req.header("Idempotency-Key")),
      await c.req.json(),
    ),
  ),
);
app.post("/v1/jobs/:id/cancel", async (c) => {
  await c.env.DB.prepare(
    "UPDATE jobs SET status='cancelled',updated_at=? WHERE id=? AND account_id=? AND kind='help' AND status IN ('pending','running')",
  )
    .bind(timestamp(), c.req.param("id"), c.get("account").id)
    .run();
  return c.json({ ok: true });
});
app.get("/v1/challenges/:id", async (c) =>
  c.json(await detail(c.env, c.get("account").id, c.req.param("id"))),
);
app.post("/v1/challenges/:id/start", async (c) => {
  const a = c.get("account").id,
    id = c.req.param("id");
  await ownedChallenge(c.env, a, id);
  await c.env.DB.prepare(
    "UPDATE challenges SET lifecycle='in_progress' WHERE id=? AND account_id=? AND lifecycle='ready'",
  )
    .bind(id, a)
    .run();
  return c.json(await detail(c.env, a, id));
});
app.put("/v1/challenges/:id/draft", async (c) => {
  const a = c.get("account").id,
    id = c.req.param("id"),
    command = requireCommand(c.req.header("Idempotency-Key"));
  await ownedChallenge(c.env, a, id);
  const { answer, revision } = answerSchema.parse(await c.req.json());
  const old = await c.env.DB.prepare(
    "SELECT command_id,revision FROM sessions WHERE challenge_id=?",
  )
    .bind(id)
    .first<{ command_id: string; revision: number }>();
  if (old?.command_id === command) return c.json({ revision: old.revision });
  const writes = await c.env.DB.batch([
    c.env.DB.prepare(
      "UPDATE sessions SET answer=?,revision=revision+1,command_id=?,updated_at=? WHERE challenge_id=? AND revision=? AND EXISTS(SELECT 1 FROM challenges WHERE id=? AND lifecycle IN ('ready','in_progress')) RETURNING revision",
    ).bind(answer, command, timestamp(), id, revision, id),
    c.env.DB.prepare(
      "UPDATE challenges SET lifecycle='in_progress' WHERE id=? AND account_id=? AND lifecycle='ready' AND EXISTS(SELECT 1 FROM sessions WHERE challenge_id=? AND command_id=?)",
    ).bind(id, a, id, command),
  ]);
  const row = writes[0].results[0];
  if (!row)
    throw new Fault(
      "revision_conflict",
      409,
      "The cloud answer changed. Choose which draft to keep.",
    );
  return c.json(row);
});
app.post("/v1/challenges/:id/complete", async (c) => {
  const a = c.get("account").id,
    id = c.req.param("id"),
    command = requireCommand(c.req.header("Idempotency-Key"));
  const body = answerSchema.parse(await c.req.json());
  await complete(
    c.env,
    a,
    id,
    command,
    body.answer,
    body.revision,
    await settingsFor(c.env, a),
    body.receipts ?? [],
  );
  return c.json(await detail(c.env, a, id));
});
app.post("/v1/challenges/:id/skip", async (c) => {
  const a = c.get("account").id,
    id = c.req.param("id");
  await ownedChallenge(c.env, a, id);
  await c.env.DB.batch([
    c.env.DB.prepare(
      "UPDATE challenges SET lifecycle='skipped' WHERE id=? AND account_id=? AND lifecycle IN ('ready','in_progress')",
    ).bind(id, a),
    c.env.DB.prepare(
      "UPDATE jobs SET status='cancelled' WHERE challenge_id=? AND status IN ('pending','running')",
    ).bind(id),
  ]);
  return c.json({ ok: true });
});
app.post("/v1/challenges/:id/example", async (c) => {
  const a = c.get("account").id,
    id = c.req.param("id"),
    command = requireCommand(c.req.header("Idempotency-Key"));
  await ownedChallenge(c.env, a, id);
  const existing = await c.env.DB.prepare(
    "SELECT data FROM examples WHERE challenge_id=?",
  )
    .bind(id)
    .first<{ data: string }>();
  if (existing) return c.json({ example: parseJSON(existing.data) });
  await consumeUsage(c.env, a, "reveal", 10);
  return c.json(
    await createJob(c.env, a, command, "reveal", id, {
      settings: await settingsFor(c.env, a),
    }),
    202,
  );
});
app.get("/v1/jobs/:id", async (c) => {
  const job = await c.env.DB.prepare(
    "SELECT id,kind,status,error,challenge_id FROM jobs WHERE id=? AND account_id=?",
  )
    .bind(c.req.param("id"), c.get("account").id)
    .first();
  if (!job) throw new Fault("not_found", 404, "Operation not found.");
  return c.json(job);
});
app.post("/v1/jobs/:id/retry", async (c) => {
  const a = c.get("account").id,
    old = await c.env.DB.prepare(
      "SELECT * FROM jobs WHERE id=? AND account_id=?",
    )
      .bind(c.req.param("id"), a)
      .first<Job>();
  if (!old || old.status !== "failed" || old.kind === "help")
    throw new Fault("not_retryable", 409, "This operation cannot be retried.");
  const id = requireCommand(c.req.header("Idempotency-Key"));
  await consumeUsage(c.env, a, old.kind, old.kind === "summarize" ? 20 : 10);
  const job = await createJob(c.env, a, id, old.kind, old.challenge_id, {
    ...parseJSON<object>(old.input),
    settings: await settingsFor(c.env, a),
  });
  await c.env.DB.prepare(
    "UPDATE jobs SET status='cancelled' WHERE id=? AND status='failed'",
  )
    .bind(old.id)
    .run();
  return c.json(job, 202);
});
app.get("/v1/sessions", async (c) => {
  const a = c.get("account").id;
  const cursor = c.req.query("cursor");
  let after: { at: string; id: string } | null = null;
  if (cursor) {
    try {
      after = z
        .object({ at: z.string(), id: z.string().uuid() })
        .parse(JSON.parse(atob(cursor)));
    } catch {
      throw new Fault("invalid_cursor", 400, "Invalid history cursor.");
    }
  }
  const search = (c.req.query("q") ?? "").slice(0, 160);
  const rows = await c.env.DB.prepare(
    `SELECT c.*,r.data AS reflection FROM challenges c LEFT JOIN reflections r ON r.challenge_id=c.id WHERE c.account_id=? AND c.lifecycle='completed' AND (?='' OR instr(lower(json_extract(c.data,'$.title')),lower(?))>0 OR instr(lower(json_extract(c.data,'$.topic')),lower(?))>0) AND (? IS NULL OR c.completed_at<? OR (c.completed_at=? AND c.id<?)) ORDER BY c.completed_at DESC,c.id DESC LIMIT 26`,
  )
    .bind(
      a,
      search,
      search,
      search,
      after?.at ?? null,
      after?.at ?? null,
      after?.at ?? null,
      after?.id ?? null,
    )
    .all<ChallengeRow & { reflection: string | null }>();
  const page = rows.results.slice(0, 25),
    last = page.at(-1);
  return c.json({
    sessions: page.map((r) => ({
      ...present(r),
      reflection: r.reflection ? parseJSON(r.reflection) : null,
    })),
    nextCursor:
      rows.results.length > 25 && last
        ? btoa(JSON.stringify({ at: last.completed_at, id: last.id }))
        : null,
  });
});
app.get("/v1/memory", async (c) => {
  const asOf = timestamp();
  const cutoff = new Date(Date.parse(asOf) - 7 * 86400000).toISOString();
  const statistics = await c.env.DB.prepare(
    "SELECT COUNT(*) AS completed, COALESCE(SUM(CASE WHEN completed_at>=? AND completed_at<=? THEN 1 ELSE 0 END),0) AS lastSevenDays FROM challenges WHERE account_id=? AND lifecycle='completed'"
  ).bind(cutoff, asOf, c.get("account").id).first<{ completed: number; lastSevenDays: number }>();
  const rows = await c.env.DB.prepare(
    "SELECT c.*,r.data AS reflection FROM challenges c LEFT JOIN reflections r ON r.challenge_id=c.id WHERE c.account_id=? AND c.lifecycle='completed' ORDER BY c.completed_at DESC LIMIT 100",
  )
    .bind(c.get("account").id)
    .all<ChallengeRow & { reflection: string | null }>();
  const counts = new Map<
    string,
    { label: string; kind: string; sessionIds: string[] }
  >();
  for (const row of rows.results) {
    if (!row.reflection) continue;
    const r = parseJSON<{ strengths: string[]; gaps: string[] }>(
      row.reflection,
    );
    for (const kind of ["strengths", "gaps"] as const)
      for (const label of new Set(
        r[kind].map((label) => label.trim().toLowerCase()),
      )) {
        const key = `${kind}:${label.toLowerCase()}`;
        const value = counts.get(key) ?? { label, kind, sessionIds: [] };
        value.sessionIds.push(row.id);
        counts.set(key, value);
      }
  }
  return c.json({
    statistics: { ...statistics, asOf },
    sessions: rows.results.map((r) => ({
      ...present(r),
      reflection: r.reflection ? parseJSON(r.reflection) : null,
    })),
    patterns: [...counts.values()]
      .filter((v) => v.sessionIds.length >= 2)
      .sort((a, b) => b.sessionIds.length - a.sessionIds.length)
      .slice(0, 8),
  });
});
app.delete("/v1/challenges/:id", async (c) => {
  const id = c.req.param("id"),
    a = c.get("account").id;
  await ownedChallenge(c.env, a, id);
  await c.env.DB.prepare("DELETE FROM challenges WHERE id=? AND account_id=?")
    .bind(id, a)
    .run();
  return c.json({ ok: true });
});
app.put("/v1/credential", async (c) => {
  const { key } = z
    .object({ key: z.string().trim().min(10).max(1000) })
    .parse(await c.req.json());
  const result = await fetch("https://openrouter.ai/api/v1/key", {
    headers: { Authorization: `Bearer ${key}` },
    signal: AbortSignal.timeout(15000),
  });
  if (!result.ok)
    throw new Fault(
      "credential_invalid",
      422,
      "OpenRouter could not validate that key.",
    );
  const a = c.get("account").id,
    id = uuid();
  const ciphertext = await encrypt(c.env, key, `${a}:${id}`);
  await c.env.DB.batch([
    c.env.DB.prepare(
      "INSERT INTO credentials(id,account_id,ciphertext,key_version,suffix,created_at) VALUES(?,?,?,?,?,?) ON CONFLICT(account_id) DO UPDATE SET id=excluded.id,ciphertext=excluded.ciphertext,key_version=excluded.key_version,suffix=excluded.suffix,created_at=excluded.created_at",
    ).bind(
      id,
      a,
      ciphertext,
      c.env.CREDENTIAL_KEY_VERSION,
      key.slice(-4),
      timestamp(),
    ),
    c.env.DB.prepare(
      "UPDATE jobs SET status='cancelled' WHERE account_id=? AND status IN ('pending','running') AND json_extract(input,'$.settings.aiMode')='byok'",
    ).bind(a),
    c.env.DB.prepare(
      "UPDATE requests SET status='interrupted' WHERE account_id=? AND status='running'",
    ).bind(a),
  ]);
  return c.json({ suffix: key.slice(-4) });
});
app.delete("/v1/credential", async (c) => {
  const a = c.get("account").id;
  await c.env.DB.batch([
    c.env.DB.prepare("DELETE FROM credentials WHERE account_id=?").bind(a),
    c.env.DB.prepare(
      "UPDATE requests SET status='interrupted' WHERE account_id=? AND status='running'",
    ).bind(a),
    c.env.DB.prepare(
      "UPDATE jobs SET status='cancelled' WHERE account_id=? AND status IN ('pending','running') AND json_extract(input,'$.settings.aiMode')='byok'",
    ).bind(a),
  ]);
  return c.json({ ok: true });
});
app.post("/v1/devices", async (c) => {
  const token = uuid() + uuid(),
    id = uuid();
  await c.env.DB.prepare(
    "INSERT INTO devices(id,account_id,token_hash,expires_at) VALUES(?,?,?,?)",
  )
    .bind(
      id,
      c.get("account").id,
      await hash(token),
      new Date(Date.now() + 30 * 86400000).toISOString(),
    )
    .run();
  return c.json({
    id,
    token,
    expiresAt: new Date(Date.now() + 30 * 86400000).toISOString(),
  });
});
app.delete("/v1/devices/:id", async (c) => {
  await c.env.DB.prepare("DELETE FROM devices WHERE id=? AND account_id=?")
    .bind(c.req.param("id"), c.get("account").id)
    .run();
  return c.json({ ok: true });
});
app.delete("/v1/account", async (c) => {
  const a = c.get("account").id,
    id = requireCommand(c.req.header("Idempotency-Key"));
  await createJob(c.env, a, id, "delete_account", null, {});
  await c.env.DB.batch([
    c.env.DB.prepare("UPDATE accounts SET status='deleting' WHERE id=?").bind(
      a,
    ),
    c.env.DB.prepare("DELETE FROM devices WHERE account_id=?").bind(a),
  ]);
  return c.json({ status: "deleting" }, 202);
});
app.get("/v1/requests/:id", async (c) => {
  const row = await c.env.DB.prepare(
    "SELECT id,status FROM requests WHERE id=? AND account_id=?",
  )
    .bind(c.req.param("id"), c.get("account").id)
    .first();
  if (!row) throw new Fault("not_found", 404, "Request not found.");
  return c.json(row);
});
app.post("/v1/requests/:id/cancel", async (c) => {
  await c.env.DB.prepare(
    "UPDATE requests SET status='interrupted' WHERE id=? AND account_id=? AND status='running'",
  )
    .bind(c.req.param("id"), c.get("account").id)
    .run();
  return c.json({ ok: true });
});
app.post("/v1/challenges/:id/coach", async (c) => {
  const a = c.get("account").id,
    id = c.req.param("id"),
    request = requireCommand(c.req.header("Idempotency-Key"));
  const { question } = z
    .object({
      question: z.string().max(4000).default("Give me one useful hint."),
    })
    .parse(await c.req.json());
  const context = await detail(c.env, a, id);
  if (!["ready", "in_progress"].includes(String(context.lifecycle)))
    throw new Fault(
      "session_closed",
      409,
      "This practice session is complete.",
    );
  if (
    await c.env.DB.prepare("SELECT id FROM requests WHERE id=?")
      .bind(request)
      .first()
  )
    throw new Fault(
      "request_exists",
      409,
      "Check the existing request before retrying.",
    );
  await consumeUsage(c.env, a, "coach", 50);
  const now = timestamp();
  try {
    await c.env.DB.prepare(
      "INSERT INTO requests(id,account_id,challenge_id,status,created_at,updated_at) VALUES(?,?,?,'running',?,?)",
    )
      .bind(request, a, id, now, now)
      .run();
  } catch {
    throw new Fault(
      "request_running",
      409,
      "Another coaching request is still running.",
    );
  }
  const revision = Number(context.session?.revision ?? 0),
    controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 60000);
  return streamSSE(c, async (stream) => {
    stream.onAbort(() => controller.abort());
    let text = "";
    try {
      const settings = await settingsFor(c.env, a);
      const response = await provider(
        c.env,
        a,
        settings,
        messagesFor("coach", { ...context, latestQuestion: question }),
        { stream: true, signal: controller.signal },
      );
      if (!response.body) throw new Error("empty");
      for await (const delta of textDeltas(response.body, (usage) =>
        recordUsage(c.env, a, settings, "coach", usage),
      )) {
        text += delta;
        await stream.writeSSE({
          event: "delta",
          data: JSON.stringify({ requestId: request, text: delta }),
        });
      }
      if (!text.trim()) throw new Error("empty");
      await c.env.DB.batch([
        c.env.DB.prepare(
          "INSERT INTO turns(id,challenge_id,request_id,role,text,state,answer_revision,created_at) SELECT ?,?,?,'user',?,'completed',?,? WHERE EXISTS(SELECT 1 FROM requests r JOIN challenges c ON c.id=r.challenge_id JOIN accounts a ON a.id=r.account_id WHERE r.id=? AND r.status='running' AND c.lifecycle IN ('ready','in_progress') AND a.status='active')",
        ).bind(uuid(), id, request, question, revision, now, request),
        c.env.DB.prepare(
          "INSERT INTO turns(id,challenge_id,request_id,role,text,state,answer_revision,created_at) SELECT ?,?,?,'assistant',?,'completed',?,? WHERE EXISTS(SELECT 1 FROM turns WHERE request_id=? AND role='user')",
        ).bind(uuid(), id, request, text, revision, timestamp(), request),
        c.env.DB.prepare(
          "UPDATE requests SET status='completed',updated_at=? WHERE id=? AND status='running' AND EXISTS(SELECT 1 FROM turns WHERE request_id=? AND role='assistant')",
        ).bind(timestamp(), request, request),
      ]);
      if (
        !(await c.env.DB.prepare(
          "SELECT id FROM requests WHERE id=? AND status='completed'",
        )
          .bind(request)
          .first())
      )
        throw new Error("request_cancelled");
      await stream.writeSSE({
        event: "completed",
        data: JSON.stringify({ requestId: request }),
      });
    } catch {
      await c.env.DB.prepare(
        "UPDATE requests SET status='interrupted',updated_at=? WHERE id=? AND status='running'",
      )
        .bind(timestamp(), request)
        .run();
      await stream
        .writeSSE({
          event: "failed",
          data: JSON.stringify({
            requestId: request,
            message: "Coaching was interrupted. Your answer is safe.",
          }),
        })
        .catch(() => {});
    } finally {
      clearTimeout(timeout);
    }
  });
});
export default {
  fetch: app.fetch,
  scheduled: (_event: ScheduledController, env: Env, ctx: ExecutionContext) =>
    ctx.waitUntil(reconcile(env)),
};
