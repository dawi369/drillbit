# Productionize: plans, paywall, voice metering

Status: implemented 10 October 2026 (phases 0–4); live-service and device verification pending the items under “What I need from you”.

## Decisions (from product owner, 10 Oct)

| | Free | Pro |
|---|---|---|
| Reps (questions) | **3 per UTC day**. Replaces the one-per-week free rep. Daily automatic question stays off. | Unlimited, fair-use cap `PRO_REPS_PER_DAY` (default 30). Daily automatic question on. |
| Voice sessions | **First 3 sessions free (lifetime)**, then **1 free "taste" every 7 days**. Session cap **3 min**. | Unlimited, fair-use caps `PRO_VOICE_STARTS_PER_DAY` (20) and `PRO_VOICE_SESSION_MINUTES` (20). |
| Follow-ups / nudges inside a rep | Existing `FREE_REP_FOLLOW_UPS` (8) / `FREE_REP_NUDGES` (2) | Uncapped |
| Recall, Library, past feedback | Free | Free |

Rationale for the voice taste cadence: three free sessions let the first feedback be acted on; a weekly 3-minute session keeps voice visible to free users without a meaningful cost floor (3 min × 1/week per free user). Caps are env-configurable so they can move once `scripts/measure-inference.ts` has real per-minute numbers.

Fair-use caps are not shown to Pro users anywhere; hitting one returns a plain "that's a lot for one day, back tomorrow" message.

## Architecture

### Entitlement source of truth: Apple, verified on the Worker
Superwall draws the paywall and runs the StoreKit purchase. The Worker never trusts the client's claim of "Pro"; it stores an entitlement only from:

1. `POST /v1/entitlement` with a StoreKit 2 signed transaction (JWS). The Worker verifies the x5c chain against the Apple Root CA G3, checks `bundleId == dawi.drillbit`, product id in the known set, and stores `{ account_id, original_transaction_id, product_id, expires_at, environment, status }`.
2. App Store Server Notifications V2 at `POST /apple/notifications` (renewal, expiry, refund, revoke, grace period). Same JWS verification. Keyed by `original_transaction_id`, mapped back to the account that first posted it.

Plan resolution is one function `planFor(env, account)`: `pro` when an entitlement row is active (`expires_at > now` or in grace), else `free`. Env allowlists stay as dev overrides (`DEVELOPER_ACCOUNTS`, `VOICE_UNLIMITED_ACCOUNTS`, `PRACTICE_UNLIMITED_ACCOUNTS`) and are treated as `pro`.

Why not Superwall webhooks: Superwall's subscription status in-app is derived from StoreKit anyway; verifying Apple's own signed data on the server is the smallest trusted path and keeps the Worker independent of a vendor. Superwall stays a UI/experiment layer.

Implementation note: try `@apple/app-store-server-library` under `nodejs_compat` first; if it does not run on Workers, verify the x5c chain with WebCrypto (ECDSA P-256) directly. Either way, tests use a fixture chain generated in the test, not Apple's production root.

### Limits live in one module
New `apps/api/src/plans.ts`:
- `planFor(env, account)` → `"free" | "pro"`.
- `limits(plan, env)` → `{ repsPerDay, voiceSessionSeconds, voiceStartsPerDay, voiceFreeLifetime, voiceTasteIntervalDays, dailyQuestion }`.
- `repAllowance(env, account)` and `voiceAllowance(env, account)` return `{ available, remaining, limit, resetsAt, reason }` and are what `bootstrap.practice` and `bootstrap.capabilities.voice` expose.

Rep accounting reuses the existing `freeRepAt` stamp on challenges/generation jobs (atomic insert check in `practice-gate.ts`); the window changes from "one in 7 days" to "fewer than N since UTC midnight". Voice accounting reuses `usage(kind='voice_start')` for the daily counters plus a lifetime count from `voice_sessions`. Taste cadence: latest `voice_sessions.created_at` for the account after the first three.

Session cap is server-issued: `POST /v1/challenges/:id/voice` returns `expiresAt` from the plan's cap (not a fixed 15 min), and `capabilities.voice.sessionSeconds` tells the client its deadline. The client's `LiveVoice.sessionLimit` becomes that value. Events after `expires_at` are already rejected (`inactive`). Hard-stopping the provider session from the server is not available in the current transport; the client deadline plus event rejection bounds cost. Flagged as a known limit.

### Bootstrap contract additions
```
account.plan: "free" | "pro"
practice: { available, remaining, limit, resetsAt, reason? }     // replaces freeReps/nextFreeRepAt
capabilities.voice: { available, remaining, limit, resetsAt, sessionSeconds, reason?, checkedAt }
```
`openapi.json` and `packages/contracts/fixtures` updated; native DTOs keep optional fields so older builds decode.

### iOS
- SuperwallKit via SPM in `project.yml`. Configure at launch, `identify` with the Drillbit account id after sign-in, `reset` on sign-out.
- Two placements: `practice_rep` behind `AppModel.mayStartRep` (already the single choke point), `voice_session` in `enterVoice` when the server says no allowance. Paywall shows only when the Worker denies; a `402 practice_gate` / `voice_gate` from the server also triggers it, so the server stays authoritative.
- `EntitlementSync`: observes `Transaction.updates` and `Transaction.currentEntitlements`, posts the JWS to `/v1/entitlement`, then refreshes bootstrap. Also runs on foreground and after Superwall reports a purchase/restore.
- Settings: plan row ("Free · 3 reps a day" / "Pro"), Manage subscription (`AppStore.showManageSubscriptions`), Restore purchases.
- Home copy: "2 of 3 reps left today", "Reps come back at 2 AM". Voice idle copy: "First 3 on us", "Your weekly voice session is ready", "Next free voice session Thursday". No duration shown on free; Pro shows nothing.
- Fixtures: `--fixture-plan=free|pro`, `--fixture-reps-left=N`, `--fixture-voice-taste`. UI tests cover gate → paywall placement → unlock → rep starts.
- Local StoreKit testing: `apps/ios/Config/Drillbit.storekit` with the two products so purchases work in the simulator without App Store Connect.

### Voice-room cleanup (agreed earlier, ships first)
Start muted; crossfade room ↔ workspace; remove the status line; dock lower; left control becomes **Text** (ends voice, lands in the editor with keyboard up); drop "Up to 10 min"; 80-pt circular mic with ring and live glow; tests updated.

## Phases (autopilot order)

0. Voice-room cleanup. Build + UI tests.
1. `plans.ts`, daily reps, voice allowance + server-issued cap, Pro fair-use caps, bootstrap fields, OpenAPI + fixtures. D1 tests: concurrent rep starts spend exactly N; taste cadence; cap applied to `expiresAt`; allowlist override.
2. `entitlements` migration, JWS verification, `POST /v1/entitlement`, `POST /apple/notifications`, plan resolution. Tests with generated cert chain: valid, wrong bundle, expired, revoked, replay, notification before client post.
3. iOS: DTOs, `EntitlementSync`, Superwall placements, Settings rows, Home/voice copy, fixtures, `.storekit` file. Unit + UI tests, `scripts/check-ios.sh`.
4. Docs: `architecture.md` section replaced, `operations.md` gets the Apple/Superwall setup and secrets. Report splits compiled/tested vs live-verified vs device-verified.

## What I need from you

Blocking before phase 3 can be live-verified (phases 0–2 and the iOS code can proceed without them):

1. **App Store Connect**
   - Create a subscription group "Drillbit Pro" with products `dawi.drillbit.pro.monthly` and `dawi.drillbit.pro.yearly` (or tell me your ids). Prices are yours; the vision doc assumes a 7-day free trial offered on the paywall only — confirm or drop.
   - App Store Server Notifications V2: set both Sandbox and Production URLs to `https://<api-host>/apple/notifications` once deployed (I'll give the exact host).
   - A Sandbox tester Apple ID signed in on your test device.
2. **Superwall**
   - Account + iOS app, give me the **public** API key (it ships in the binary; not a secret, but goes through `apps/ios/Config`, not git-tracked plaintext if you prefer).
   - In the dashboard: placements `practice_rep` and `voice_session`, one paywall attached, products linked to the ids above. I write the copy for the paywall if you want; the paywall itself is remote.
3. **Worker config**
   - Confirm the API host for production and that `wrangler.jsonc` production env exists (today only `drillbit-api-development`).
   - I'll add vars `APPLE_BUNDLE_ID=dawi.drillbit`, `PRO_REPS_PER_DAY`, `PRO_VOICE_STARTS_PER_DAY`, `PRO_VOICE_SESSION_MINUTES`, `FREE_REPS_PER_DAY=3`, `FREE_VOICE_LIFETIME=3`, `FREE_VOICE_TASTE_DAYS=7`, `FREE_VOICE_SESSION_MINUTES=3`. No new secrets are required for JWS verification. If you want transaction-history lookups for support, you'd also create an App Store Server API key (issuer id, key id, .p8) — optional, not in this plan.
4. **Decisions to confirm**
   - 7-day voice taste cadence and 3-minute free cap (my proposal).
   - Pro fair-use defaults (30 reps/day, 20 voice starts/day, 20 min/session).
   - Day boundary stays UTC midnight (existing behaviour; shown in local time).
   - Free accounts still get no automatic daily question.

## Risks
- Apple JWS verification on Workers: library compatibility unverified; fallback is manual WebCrypto chain verification (more code, same tests).
- Provider voice session cannot be force-closed server-side; a tampered client could overrun the cap until `expires_at` rejects events. Cost exposure is bounded by the cap window, not zero.
- Superwall SDK API names (`register(placement:)`, `identify`, `subscriptionStatus`) to be checked against the SPM version resolved; I will not guess signatures.
- Refund/revoke lag: entitlement flips when Apple's notification lands; until then a refunded user keeps Pro.
