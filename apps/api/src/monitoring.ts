import * as Sentry from "@sentry/cloudflare";
import { z } from "zod";
import { Fault } from "./domain";
import type { Env } from "./platform";

type SentryEvent = Parameters<NonNullable<Sentry.CloudflareOptions["beforeSend"]>>[0];
type Breadcrumb = Parameters<NonNullable<Sentry.CloudflareOptions["beforeBreadcrumb"]>>[0];

/** Quoted text is dropped: JSON parse errors quote their input, which can be model output or an answer. */
export const unquoted = (text: string) => text.replace(/"[^"]*"?|'[^']*'?|`[^`]*`?/g, "…").slice(0, 160);
const pathOnly = (url?: string) => url?.split(/[?#]/)[0];

/**
 * Sentry (t23/drillbit-api) for failures nobody expected: bugs, provider outages and jobs that gave up. Off without
 * `SENTRY_DSN` (tests, local dev). An event keeps the route pattern, a code, the error's type and stack, and nothing
 * else: no bodies, headers, query strings, account ids, IP addresses or practice text.
 */
export function sentryOptions(env: Env): Sentry.CloudflareOptions {
  return {
    dsn: env.SENTRY_DSN,
    environment: env.SENTRY_ENVIRONMENT ?? "development",
    // Collect nothing about people or payloads; the scrub below is the second guard.
    dataCollection: {
      userInfo: false, cookies: false, httpHeaders: false, httpBodies: [], urlQueryParams: false,
      genAI: { inputs: false, outputs: false }, databaseQueryData: false, stackFrameVariables: false,
    },
    tracesSampleRate: 0,
    beforeSend: scrubEvent,
    beforeBreadcrumb: (crumb: Breadcrumb) => {
      // Console lines are already sent as events where they matter; fetch crumbs keep the host and path only.
      if (crumb.category === "console") return null;
      if (crumb.data?.url) crumb.data = { url: pathOnly(String(crumb.data.url)), method: crumb.data.method, status_code: crumb.data.status_code };
      return crumb;
    },
  };
}

export function scrubEvent(event: SentryEvent): SentryEvent {
  if (event.request) event.request = { url: pathOnly(event.request.url), method: event.request.method };
  delete event.user;
  delete event.extra;
  for (const exception of event.exception?.values ?? []) if (exception.value) exception.value = unquoted(exception.value);
  if (event.message) event.message = unquoted(event.message);
  return event;
}

/** The error's type and stack frames with its message cleaned; a ZodError keeps field paths and issue codes only. */
export function scrubbed(error: unknown): Error {
  if (error instanceof Fault) return error;
  const name = error instanceof Error ? error.name : "NonError";
  const message = error instanceof z.ZodError
    ? error.issues.map(issue => `${issue.path.join(".") || "(root)"} ${issue.code}`).join("; ").slice(0, 160)
    : error instanceof Error ? unquoted(error.message) : "A non-error value was thrown";
  const clean = new Error(message);
  clean.name = name;
  const frames = error instanceof Error ? (error.stack ?? "").split("\n").filter(line => /^\s+at /.test(line)) : [];
  clean.stack = [`${name}: ${message}`, ...frames].join("\n");
  return clean;
}

/** Reports a failure worth knowing about, tagged for grouping (route, job kind, code). A no-op when Sentry is off. */
export function reportFailure(error: unknown, tags: Record<string, string>) {
  if (!Sentry.isEnabled()) return;
  Sentry.captureException(scrubbed(error), { tags });
}
