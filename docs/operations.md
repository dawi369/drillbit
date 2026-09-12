# Development and operations

## Local verification

Prerequisites: Bun, Xcode 26+, a matching iOS simulator runtime, and XcodeGen (`brew install xcodegen`).

```sh
bun install --frozen-lockfile
bun run typecheck
bun run test
swift test --package-path apps/ios -j 2
bun run ios:generate
```

Use `bun run test`, not Bun's native test runner, for the API: the suite uses the Cloudflare Workers runtime and actual D1 SQL behavior. The Swift package tests persistence/contract logic on macOS; they do not substitute for physical iPhone acceptance.

Open `apps/ios/Drillbit.xcodeproj` and select the Drillbit scheme. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`, fill the public API URL, Clerk publishable key and signing team. That local file is ignored. The simulator debug launch argument `--fixtures` selects synthetic content and never contacts a provider. Fixture mode cannot be enabled by launch arguments in Release builds.

For local API work, set Worker secrets in `apps/api/.dev.vars` and apply local migrations with `bun run --cwd apps/api db:local`, then `bun run dev`. An encryption key was generated into the ignored `.dev.vars`; preserve that file and its permissions. Never put server secrets in Xcode configuration or app resources.

## Clerk and Apple configuration

Create separate Clerk development and production applications. Enable native Sign in with Apple for bundle ID `dawi.drillbit`. Configure Apple credentials in Clerk. Create a JWT template named `drillbit` with audience claim `"aud": "drillbit"` and a short lifetime (60 seconds). The app requests that template explicitly. Set the exact Clerk instance issuer in Wrangler and its public publishable key in Xcode.

The app keeps Clerk credentials in its own Keychain access group `<TeamPrefix>dawi.drillbit`; only widget credentials use the shared group. The app/extension require application group `group.dawi.drillbit` and shared Keychain group `<TeamPrefix>dawi.drillbit.shared`; the app also requires Sign in with Apple. Enable the corresponding capabilities and provisioning profiles in the Apple developer account. Native keyboard dictation needs no app microphone permission.

Worker secrets:
- `CLERK_SECRET_KEY`: used only for account deletion.
- `OPENROUTER_API_KEY`: managed requests; use a fresh restricted/budgeted provider key. Do not reuse a key previously embedded in the Expo build.
- `CREDENTIAL_KEY`: 32 random bytes, base64 encoded. Already generated for development; never regenerate casually while BYOK credentials exist.

`MANAGED_AI_ENABLED` is enabled for the configured development deployment. The existing OpenRouter key was validated and installed as a Worker secret. New environments must install their own secrets and set provider spending limits before enabling managed AI. `CLERK_AUDIENCE` is `drillbit`. BYOK key-version mismatches require re-entry; a future key rotation must preserve the previous key long enough to re-encrypt or explicitly invalidate stored credentials.

## Development deployment

The provisioned development resources are:
- Worker: `drillbit-api-development`
- D1: `drillbit-development` (Western Europe location hint)
- Workflow: `drillbit-jobs-development`
- URL: https://drillbit-api-development.david-erwin-cz68.workers.dev

From `apps/api`:
```sh
./node_modules/.bin/wrangler d1 migrations apply drillbit-development --remote
./node_modules/.bin/wrangler deploy
./node_modules/.bin/wrangler secret put CLERK_SECRET_KEY
./node_modules/.bin/wrangler secret put OPENROUTER_API_KEY
```

Create invite codes using `bun scripts/invite.ts`; it writes the code to an ignored local file and outputs only the SQL containing its hash. Execute that SQL against the intended environment. Keep invitation codes private.

External TestFlight and production environments must use their own Worker, database, Workflow, Clerk instance and secrets. An internal-only build for the owner’s physical-device development checks may use the current development environment; mark the upload TestFlight Internal Only. The checked-in deployment is development only. Do not repoint it at an existing Operloom or Assistant-MK1 resource.

## Health, jobs and spending

`GET /health` checks the running service; unauthorized `/v1/bootstrap` must return 401. Monitor Workers error/latency metrics and D1 job states. Failed summaries can be retried in the app. Stable workflow IDs prevent duplicate dispatch; help uses explicit retries while other jobs retain bounded retries; neither can guarantee exactly-once provider billing after ambiguous network failures.

Switch `MANAGED_AI_ENABLED=false` and redeploy to stop new managed model requests. Per-account counters additionally cap challenge, coach and example operations; BYOK is still subject to infrastructure limits. A shared 100-attempt daily cap also bounds provider calls from scheduled work and retries. AI run metadata records structured and streamed token usage when returned by the provider. No prompt/answer bodies are intentionally logged.

Failed account-deletion jobs require operator attention because the account is disabled; restore the Clerk secret/service and restart the workflow from Cloudflare. Do not silently reactivate the account.

## Backup and rollback

Before schema changes, export D1 using `wrangler d1 export drillbit-development --remote --output <private-backup.sql>` or record a D1 Time Travel bookmark. Keep exports private: they can contain practice data and encrypted credentials.

Test restoring exports into a separate local database, never over the running service. Database migrations are forward-only. Roll back a Worker deployment only when it is compatible with the current schema; otherwise deploy a forward fix. Keep old Workflow code compatible until its existing jobs finish. Encryption keys are separate from database backups.

## Release gate

A signed TestFlight release requires real Apple sign-in, both AI modes, cold widget launches, interrupted networking, offline completion/reconnect and account deletion on a real iPhone. The local fixture screen check is explicitly not a provider/account acceptance test. Record remaining issues in `docs/acceptance.md` rather than describing unverified paths as complete.

## Configured development identity

- Clerk application: `app_3J3qgUOGZVnbk3wbtpTOH5PKIQA` (Drillbit).
- Development instance: `ins_3J3qgRXUMkhCiy4iC4MT4Slau5O`; issuer `https://trusting-finch-496.clerk.accounts.dev`.
- Native registration: App ID prefix `7M4NDAAP73`, bundle `dawi.drillbit`; callback `dawi.drillbit://callback` is allowlisted.
- Apple, Google and GitHub are enabled in Clerk and available in the app. Apple uses the native flow; Google/GitHub use the Clerk OAuth flow through the system authentication browser.
- JWT template `drillbit`: RS256, audience `drillbit`, lifetime 60 seconds, allowed clock skew 5 seconds.
- Worker secrets installed: `CREDENTIAL_KEY`, `CLERK_SECRET_KEY`, `OPENROUTER_API_KEY`. Secret values remain in ignored local configuration and Cloudflare, never native resources.
- Apple Developer app `dawi.drillbit` has Sign in with Apple enabled. App and widget share the existing `group.dawi.drillbit`. Xcode automatic signing uses team `7M4NDAAP73`.
- A single-use development invitation is saved in the ignored `.local/drillbit-invite.txt` and its hash is installed in D1. Redeem it after the first real sign-in.

For real authentication in Simulator, run a **signed** build from Xcode. `CODE_SIGNING_ALLOWED=NO` remains suitable for compilation and isolated unit tests, but the Clerk SDK can assert when its startup Keychain operations lack entitlements. Do not launch the unsigned test artifact for authentication acceptance.

Clerk CLI is linked to the project. `clerk doctor` verifies the account/application; its root `.env` warning is expected because the app/API deliberately keep their configuration in separate locations. Production Clerk and custom production Google/GitHub OAuth credentials remain separate release work.

## Text-practice migration (9 September 2026)

Migration `0004_practice_help.sql` adds help results, revision-checked adoption events, immutable completion contexts and the one-help constraint; it also changes saved model preferences to Gemini 3.1 Flash Lite. Apply it before deploying the text-practice Worker. The private development export is `.local/before-practice-help-20260909.sql`. Existing answers and sessions are preserved.

Help request recovery uses the same stored job ID; do not create automatic replacement requests after transport failures. Native draft adoption additionally persists the command payload before sending and reconciles that exact command after interruption. Generation and reflection failures remain retriable. Do not treat successful schema validation as proof of factual model quality.

## Simulator test helper and source backup

Xcode UI tests install `DrillbitUITests-Runner` (`dawi.DrillbitUITests.xctrunner`) alongside the main app. It is a test harness, not an alternate Drillbit build. After tests finish, it can be uninstalled with `xcrun simctl uninstall <simulator-id> dawi.DrillbitUITests.xctrunner`; future UI tests recreate it. Do not uninstall `dawi.drillbit` to clean up the runner, because that would remove the app's local data.

`/Users/dawi/dev/drillbit-before-native-20260908-212600` is a 2.5 MB recovery bundle (`source.tar.gz`, `working-tree.patch`, `HEAD`), not a second active checkout. It was preserved during the native rebuild.

### Companion development rollout

Migration `0005_companion.sql` is additive. Keep the D1 export private; it includes practice data. The September 9 companion backup is `.local/before-companion-20260909.sql` (ignored by git).

`COMPANION_AUTO_ENABLED=true` enables automatic requests in the development Worker and advertises the capability in bootstrap/challenge detail. To roll back automatic help, set it to `false` in the Worker configuration and deploy; leave the migration and exposure records in place. Explicit help remains available. No production rollout was performed. The later owner-only TestFlight upload is recorded below.

Synthetic live companion tests use isolated `qa-companion-…` accounts and must clean up only the exact IDs recorded for that run. Do not delete real users or practice data. UI tests use an in-memory fixture store; the main signed `dawi.drillbit` app can be relaunched without fixture arguments afterwards. Remove `dawi.DrillbitUITests.xctrunner` after UI testing to keep the user's simulator uncluttered.


## First internal TestFlight release — 9 September 2026

Version `2.0.0` build `1` uploaded successfully with Xcode automatic distribution signing for team `7M4NDAAP73`. App Store Connect reports **Testing**, internal-only, assigned to **Owner Testing**; the account holder is **Invited**. The group has automatic distribution enabled for subsequent uploads. Installation and physical-device acceptance remain unverified.

- App Store Connect name: **Drillbit Practice**; the name “Drillbit” was unavailable. Installed app name remains **Drillbit**.
- Apple app ID: `6810226020`; bundle ID: `dawi.drillbit`.
- Internal group ID: `e242f9c8-8db6-463c-938a-c7d621b053a2` (one account-holder tester).
- [TestFlight build](https://appstoreconnect.apple.com/teams/3bb0ff9a-d238-43f8-87da-3105489e72ae/apps/6810226020/testflight/ios/dc298efa-581b-420b-b597-d7104e1fec90).
- Minimum OS: **iOS 26**. This owner-only development build uses the existing development Worker, D1 and Clerk instance; it is not a production release.
- Apple’s TestFlight email invitation installs the app. The separate Drillbit access code is redeemed inside the app after sign-in.

Release archive: `/tmp/drillbit-testflight/Drillbit.xcarchive`. Export options: `/tmp/drillbit-testflight/ExportOptions.plist` (`app-store-connect`, upload, automatic signing, `testFlightInternalTestingOnly=true`, automatic build-number management). These temporary artifacts are not durable release storage. The initial upload failed because the App Store Connect app record did not exist; creating the record and rerunning export resolved it. The successful export reported `EXPORT SUCCEEDED` and “Upload succeeded.”

For a newly prepared archive with a fresh build number, use:

```sh
xcodebuild -exportArchive -archivePath /tmp/drillbit-testflight/Drillbit.xcarchive -exportPath /tmp/drillbit-testflight/export -exportOptionsPlist /tmp/drillbit-testflight/ExportOptions.plist -allowProvisioningUpdates
```

Assistant MK1 (`6801853827`, `com.dawi369.assistantmk1`) was removed from active App Store Connect apps at the owner’s request. Its App Information page now offers **Restore App**, confirming it is in Apple’s Removed Apps list. This is not permanent erasure. This operation did not remove other apps, shared certificates, backend resources or local source.

## Settings release — build 2

On 9 September 2026 the compatible settings backend deployed successfully as `1d798d23-25d4-457d-a36e-a68b2e6a9ecf`. Health returned 200 and unauthenticated bootstrap 401. No D1 migration is needed: level fields are additive in existing JSON records, with legacy normalization on read/job execution.

Signed Release version `2.0.0` build `2` archived to `/tmp/drillbit-testflight/Drillbit-build2.xcarchive` and uploaded successfully using the existing internal-only export options. Live App Store Connect verification: processing **Complete**, build **Testing / Internal**, assigned to **Owner Testing** with one invitation. Build ID: `0936344e-6e1c-4826-a725-036c153038e4`. The build retains iOS 26 minimum and development services. See the settings section of [acceptance](acceptance.md) for verification and remaining device/prompt limits.

## Interview development rollout — 9 September 2026

D1 backup precedes additive migration `0006_interview.sql`. Development Worker `43ca2338-28c9-486b-8e36-04ca2b1c5db4` supports ordered interview turns and response retries while retaining older clients. Final signed native distribution was simulator-only. A synthetic live workflow completed; its isolated account/data was removed. Interview jobs have no automatic inference retries; users retry the response while the original answer remains committed. Keep the additive table when rolling back compatible Worker code. The new client requires interview-capable backend endpoints.

Development interview-style compatibility update (9 September 2026): Worker `aaccb3da-6ba7-4089-a45b-163b5a1b678e` accepts optional per-turn style and atomically records it with the accepted turn. No migration. Health returned 200. Native distribution for this iteration is simulator only.


10 September 2026: development Worker version `2de0e125-147e-4c43-b3c9-c28b24b18792` selects Gemini 2.5 Flash-Lite, reasoning disabled, latency-sorted providers. Health returned 200 after deployment. Existing database and stored answers are unchanged. Old 3.1 client settings remain accepted and normalized. Simulator distribution only.

### Interview stream rollout (10 September 2026)

Migration `0007_interview_streams` was applied to development D1 after backup `.local/before-interview-stream-20260910.sql`. Deploy the backend before installing the streaming client. The stream endpoint only subscribes to an existing account-owned turn; it never triggers another paid request. Reconnect interrupted subscriptions through Retry. Older clients continue reading completed challenge/interview detail. Stream text is provisional and deleted with its owning job; never use it as evidence of a completed interviewer response. No TestFlight upload was performed.

### Library rollout and practice reset — 10 September 2026

Development database: `drillbit-development` (`872d5aed-a356-4b2b-a479-aa3042478aee`). Backup: ignored `.local/before-library-reset-20260910.sql`; never publish the backup because it includes private practice/configuration data. Migration 0008 adds questions, attempt links, idempotent eligibility commands and the practice epoch/maintenance gate.

The authorized reset cleared challenges and their dependent practice content, old companion commands, non-account-deletion jobs, questions and AI-run history. It retained accounts, settings, invitations, credentials, device registrations and usage-limit accounting. Settings focus was normalized to System design. The reset advanced `practice_epoch.value`; new native builds clear old account-scoped practice queues before replay. `enabled=0` pauses scheduled reconciliation and practice mutations; `enabled=1` resumes them. Old queued jobs cannot recreate attempts after reset because result writes require surviving jobs/challenges.

Deploy compatible backend first, then install the simulator build. Latest library rollout version: `d0c78072-c3d1-421d-a944-fadd65f22527`. Provider remains Gemini 2.5 Flash Lite. No TestFlight distribution was performed. Future resets require an explicit authorized scope, verified development target, backup, maintenance gate, epoch advance and post-reset configuration/data counts.

### Inference timing and compatible rollback

Development version `2550aac2-a5e9-4014-9760-ac98c3a03c28` accepts optional atomic interview `saveDraft` requests. Keep this additive request support when rolling back other latency changes; older clients continue using synced drafts. Native Send timing is in OSLog subsystem `dawi.drillbit`, category `inference`. Worker events `inference_job_start`, `inference_headers` and `inference_first_text` separate execution wait from provider setup/stream time; no prompts or answers are logged. The Worker deployment startup estimate is not a measurement of per-job Workflow startup.

11 September personality development rollout: `b426c78b-b2f8-4ba7-81f5-3d462d57ec6a`, V3 prompt plus Gemini 3.1 Flash-Lite. No database migration. Preserve the V3 resolver when rolling back other code: queued jobs capture their prompt edition. Reverting the active default only affects newly accepted jobs. Simulator distribution only.

11 September V4 personality rollout: `ab6f37c9-16b7-4b2e-a42d-5ce2f0766c6c`. Keep V2/V3/V4 prompt resolvers and V4 model-response parsing for captured jobs. No migration. V4 substantive interview requests use low reasoning; pure social, legacy and other operations retain disabled reasoning. Rollback of the active edition affects newly captured jobs only.

## Internal TestFlight build 3 — 11 September 2026

User-authorized physical-device testing release: version `2.0.0` build `3`, bundle `dawi.drillbit`, team `7M4NDAAP73`. Signed Release archive succeeded at `/tmp/drillbit-testflight/Drillbit-build3.xcarchive`; Xcode export reported “Upload succeeded” and `EXPORT SUCCEEDED`. Export remains internal-only with automatic signing and build-number management. Minimum iOS remains 26.0; development Worker/Clerk remain unchanged. Backend personality V4 is already deployed (`ab6f37c9-16b7-4b2e-a42d-5ce2f0766c6c`) and `/health` returned `ok` during release. Voice remains disabled. Live App Store Connect showed build 3 as **Processing** after upload. Subsequent build/group queries stalled or returned an empty list despite existing builds; final processing completion and Owner Testing assignment could not be confirmed in this session. Physical-device acceptance remains pending.

## Text-practice completeness development rollout — 11 September 2026

Worker version `5a917562-5b56-4de6-a77b-5ac2eb9f0826` deployed successfully; health returned `ok`. Additive evidence and account-export contracts, selection version 2 and reflection prompt `feedback-v2` require no database migration. Existing clients and historical reflections remain supported. Current simulator build installed on iPhone 17 Pro; no TestFlight upload. Details and remaining physical checks: [completeness ledger](product-completeness.md).

Feedback runs use low reasoning; social/interview transport policy remains V4. `ai_runs.prompt_version` now records the actual edition rather than the old hardcoded practice version. Invalid structured responses still record available usage. To roll back, deploy the prior compatible Worker; retain saved reflection JSON and library records. An older Worker will not serve account export, so coordinate that rollback with native testing. Metrics are content-free Worker logs and local MetricKit counts, not a new third-party telemetry integration.

## Voice development rollout — 12 September 2026

Migration `0009_voice.sql` was applied after a private export at `.local/before-voice-20260912.sql` (mode 0600). The compatible Worker is deployed with `VOICE_ENABLED=false`. Set `OPENAI_API_KEY` in the ignored `apps/api/.dev.vars` for local testing; use `wrangler secret put OPENAI_API_KEY` to install it on the development Worker without putting it in a client build. OpenRouter credentials cannot authenticate GPT-Live. Enable the flag only for the controlled audio trial after confirming project model access. Disable it to stop new voice sessions; it does not terminate sessions already connected to the provider. See the voice foundation document for duration-cap and physical-device acceptance gaps.

### Owner voice allowance — 12 September 2026

`VOICE_UNLIMITED_ACCOUNTS` is an exact, comma-separated internal-account-ID allowlist, configured for the account verified from the owner's simulator bootstrap and remote D1 account record. It removes both daily `voice_start` and `voice_reasoning` ceilings while still recording their usage. It does not bypass service disablement, authentication, account/attempt scope, single-flight or session duration. Remove the ID and redeploy to restore normal limits. No usage rows were deleted/reset; no D1 migration was needed.

### First daily visit generation — 12 September 2026

Migration `0010_daily_visits.sql` adds account-local-date claims, applied after private backup `.local/before-daily-visits-20260912.sql`. Deploy the compatible backend before the native client using `/v1/daily-question`. Cron remains enabled for durable job recovery; it no longer schedules new AI questions. No APNs key is required for the existing local calendar reminder. Notification wording lives in `AppModel.reconcileReminder()`; rebuild the app to distribute copy changes.
