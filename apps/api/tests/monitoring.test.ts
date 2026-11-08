import { createExecutionContext, env, waitOnExecutionContext } from "cloudflare:test";
import { withSentry } from "@sentry/cloudflare";
import { expect, it } from "vitest";
import { z } from "zod";
import { Fault } from "../src/domain";
import { app } from "../src/index";
import { providerReason, scrubbed, scrubEvent, sentryOptions } from "../src/monitoring";
import type { Env } from "../src/platform";

const answer = "I would shard the users table by account id and keep a write-ahead log";

it("drops what an error quoted but keeps its type and stack frames", () => {
  let parse: unknown;
  try { JSON.parse(`{"answer": "${answer}"`); } catch (error) { parse = error; }
  const clean = scrubbed(parse);
  expect(clean.name).toBe("SyntaxError");
  expect(clean.message).not.toContain("shard");
  expect(clean.stack).not.toContain("shard");
  expect(clean.stack).toMatch(/^SyntaxError: /);
  expect(clean.stack!.split("\n").length).toBeGreaterThan(1);
});

it("reduces a ZodError to field paths and issue codes", () => {
  const result = z.object({ text: z.string().max(5), outcome: z.enum(["reply"]) }).safeParse({ text: answer, outcome: answer });
  const clean = scrubbed(result.error);
  expect(clean.message).toBe("text too_big; outcome invalid_value");
  expect(clean.stack).not.toContain("shard");
});

it("passes a Fault through: its message is a fixed string the app shows anyway", () => {
  const fault = new Fault("voice_provider", 502, "Couldn’t connect voice. Try again later.");
  expect(scrubbed(fault)).toBe(fault);
});

it("strips requests, users, extras and quoted text from every outgoing event", () => {
  const event = scrubEvent({
    type: undefined,
    message: `Model said "${answer}"`,
    request: { url: "https://api.drillbit.t23.dev/v1/challenges/abc/interview?draft=secret#x", method: "POST", headers: { Authorization: "Bearer t" }, data: answer, query_string: "draft=secret" },
    user: { id: "account" },
    extra: { body: answer },
    exception: { values: [{ type: "Error", value: `Unexpected token in "${answer}"` }] },
  });
  expect(event.request).toEqual({ url: "https://api.drillbit.t23.dev/v1/challenges/abc/interview", method: "POST" });
  expect(event.user).toBeUndefined();
  expect(event.extra).toBeUndefined();
  expect(JSON.stringify(event)).not.toContain("shard");
  expect(JSON.stringify(event)).not.toContain("secret");
});

it("stays off without a DSN and collects nothing about people or payloads", () => {
  const options = sentryOptions({} as Env);
  expect(options.dsn).toBeUndefined();
  expect(options.environment).toBe("development");
  expect(options.dataCollection).toMatchObject({ userInfo: false, cookies: false, httpHeaders: false, httpBodies: [], urlQueryParams: false });
  expect(options.tracesSampleRate).toBe(0);
  const crumb = options.beforeBreadcrumb!({ category: "fetch", data: { url: "https://openrouter.ai/api/v1/chat?key=x", method: "POST", status_code: 500, body: answer } });
  expect(crumb).toEqual({ category: "fetch", data: { url: "https://openrouter.ai/api/v1/chat", method: "POST", status_code: 500 } });
  expect(options.beforeBreadcrumb!({ category: "console", message: answer })).toBeNull();
});

it("names the deployed Worker version as the release", () => {
  const options = sentryOptions({ CF_VERSION_METADATA: { id: "version-1", tag: "", timestamp: "" } } as unknown as Env);
  expect(options.release).toBe("version-1");
});

it("reports an unexpected 5xx through withSentry with its route, code and request id, and nothing it quoted", async () => {
  const events: Parameters<typeof scrubEvent>[0][] = [];
  const worker = withSentry((bindings: Env) => ({
    ...sentryOptions(bindings),
    dsn: "https://public@o0.ingest.de.sentry.io/0",
    beforeSend: (event) => { events.push(scrubEvent(event)); return null; },
  // A fresh function: app.fetch itself is already wrapped by the module's default export, without a DSN.
  }), { fetch: (request, bindings, ctx) => app.fetch(request, bindings, ctx) } satisfies ExportedHandler<Env>);
  const send = async (request: Request, broken = false) => {
    const ctx = createExecutionContext();
    const bindings = { ...env, CF_VERSION_METADATA: { id: "version-2", tag: "", timestamp: "" } };
    if (broken) Object.defineProperty(bindings, "SUPPORT_EMAIL", { get() { throw new Error(`Template failed on "${answer}"`); } });
    const response = await worker.fetch!(request as any, bindings as unknown as Env, ctx);
    await waitOnExecutionContext(ctx);
    return response;
  };
  // A body that isn't JSON is the client's mistake: 400, and nothing reaches Sentry.
  const malformed = await send(new Request("https://api.drillbit.test/apple/notifications", { method: "POST", body: `{"signedPayload": "${answer}` }));
  expect(malformed.status).toBe(400);
  expect(events).toHaveLength(0);
  // A bug in a route is a 500 with a report. The thrown message quotes the answer, as a parse error would.
  const response = await send(new Request("https://api.drillbit.test/privacy?token=secret"), true);
  const body = await response.json<{ error: { code: string; requestId: string } }>();
  expect(response.status).toBe(500);
  expect(response.headers.get("X-Request-ID")).toBe(body.error.requestId);
  expect(events).toHaveLength(1);
  expect(events[0].tags).toMatchObject({ route: "/privacy", code: "internal", request_id: body.error.requestId });
  expect(events[0].release).toBe("version-2");
  expect(events[0].request).toEqual({ url: "https://api.drillbit.test/privacy", method: "GET" });
  // The envelope drops the SDK's own sdkProcessingMetadata; everything else is what Sentry receives.
  const { sdkProcessingMetadata: _, ...sent } = events[0];
  expect(JSON.stringify(sent)).not.toContain("shard");
  expect(JSON.stringify(sent)).not.toContain("secret");
});

it("logs a provider's rejection without the input it repeats", () => {
  const moderation = JSON.stringify({ error: { code: 403, message: `Input was flagged for "harassment": "${answer}"`, metadata: { reasons: ["harassment"], flagged_input: answer } } });
  expect(providerReason(moderation)).toBe("403 Input was flagged for …: …");
  const validation = JSON.stringify({ error: { type: "invalid_request_error", message: `Invalid value for 'session.instructions': '${answer}'` } });
  expect(providerReason(validation)).toBe("invalid_request_error Invalid value for …: …");
  expect(providerReason(`<html>bad gateway "${answer}"</html>`)).not.toContain("shard");
});

it("rate-limits the public App Store notification endpoint per IP before verifying anything", async () => {
  const keys: string[] = [];
  const limiter = (success: boolean) => ({ limit: async ({ key }: { key: string }) => { keys.push(key); return { success }; } });
  const post = async (success: boolean) => {
    const ctx = createExecutionContext();
    const response = await app.fetch(new Request("https://api.drillbit.test/apple/notifications", { method: "POST", headers: { "CF-Connecting-IP": "203.0.113.9" }, body: "{}" }), { ...env, APPLE_NOTIFICATIONS_LIMIT: limiter(success) } as unknown as Env, ctx);
    await waitOnExecutionContext(ctx);
    return response;
  };
  const limited = await post(false);
  expect(limited.status).toBe(429);
  expect(await limited.json()).toMatchObject({ error: { code: "rate_limited", retryable: true } });
  // Under the limit, the request reaches verification, which refuses an empty payload as a client error.
  expect((await post(true)).status).toBeLessThan(500);
  expect(keys).toEqual(["203.0.113.9", "203.0.113.9"]);
});
