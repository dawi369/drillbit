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
