import { expect, it } from "vitest";
import { z } from "zod";
import { Fault } from "../src/domain";
import { scrubbed, scrubEvent, sentryOptions } from "../src/monitoring";
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
