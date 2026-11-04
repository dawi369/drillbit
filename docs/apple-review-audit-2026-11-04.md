# Apple review audit — 4 November 2026

Scope: signed production rebuild and upload, Git push, and read-only inspection of the existing authenticated Dia session. No Apple metadata was edited, no items were added for review, and no review submission or release was performed. This report supersedes the 1 November local audit for the fields rechecked below.

## Remaining review work

1. **Add the app version to the review draft after selecting the new build.** Version 1.0 is `Prepare for Submission` and still selects build 16. The shared draft contains only the Drillbit Pro subscription group and its two subscriptions (`3 Items`, `Ready for Review`). Its exact warning is: **“Unable to Submit for Review. To submit your items for review, add an app version for the selected platform.”** This was read from the existing draft; Add for Review was not pressed, so further version-validation errors have not been ruled out.
2. **Refresh both subscriptions' review notes and screenshots.** Both product notes still say “use the two free questions in total,” while the live app-version description and review notes correctly say three. Both products have a screenshot, but the yearly thumbnail still shows the older “Don't stop at three” paywall, with yearly first. A current release screenshot must show the current weekly-first plans, $7.99/week, eligible $1.99 first week, and $99.99/year; verify both purchase surfaces on a phone. Product review fields are disabled while staged; correcting them requires removing and restaging those items.
3. **Record physical-device acceptance.** Section 7 of [the readiness checklist](app-store-readiness.md#7-physical-device-acceptance-you-about-45-minutes-required-before-submitting) remains unrecorded: real Apple sign-in, AI consent and providers, Sandbox purchase/restore, notifications, voice, offline recovery, widget, deletion and accessibility. Build 16 shows one install, one session and one crash in TestFlight; the cause was not diagnosed here. Compilation and earlier service traffic do not close this gate.
4. **Resolve the sign-in field mismatch.** The version's `Sign-in required` checkbox is unchecked, while its notes correctly describe required Sign in with Apple with self-service account creation. Verify the reviewer access configuration before submission; no shared credentials were created or entered.

## Verified portal state

| Area | Observed on 4 November |
| --- | --- |
| Agreements and compliance | Free and Paid Apps agreements Active; bank and U.S. tax form summary Active; Digital Services Act Active (27 countries/regions). No details opened or changed. |
| App Privacy | **Published a day ago**. All 10 expected types are present: Email Address, User ID, Audio Data, Other User Content, Purchase History, Product Interaction, Crash Data, Performance Data, Other Diagnostic Data, Customer Support. App Functionality throughout; diagnostics and Customer Support are not linked, the other six are linked. Preview has linked and nonlinked categories, no tracking category. Matches the native privacy manifest. The previous unpublished-label blocker is resolved. |
| Identity and notifications | Drillbit Practice; subtitle System design interview prep; Education / Productivity; 13+ in 172 territories with regional exceptions. Content Rights saved. Both production and Sandbox server URLs are `https://api.drillbit.t23.dev/apple/notifications`; protocol version not exposed in this summary. App-level DSA declaration is non-trader; no declaration changed. |
| App version copy | Three lifetime free questions and one voice mock up to 10 minutes; Pro up to 10 reps/day and 75 voice minutes/week. Review notes also specify 60 minutes/day and 20 minutes/session. Support URL and contact fields present; manual release selected. |
| Screenshots | Six uploaded large Dynamic Island screenshots, inherited by the required medium display (`Using Existing Assets`). Files: welcome, interview, example, home, recall, library. No missing screenshot set observed. Current UI/content accuracy was not audited frame by frame. |
| Subscriptions | Weekly and yearly plus group all `Ready for Review`, both level 1; English display names and fair-use descriptions present; all countries/regions selected; Family Sharing off. |
| Pricing | Product notes state $7.99/week, $1.99 first week for eligible new subscribers, $99.99/year. Yearly current pricing grid has 175 territories, zero introductory offers and zero upcoming changes; several USD territories show $99.99. US price and weekly offer schedule were not independently reopened in this pass. |
| Optional assets | New product-page Header has 0 of 1 asset. Subscription promotion images are absent and explicitly optional. No need to create these to resolve the observed draft warning. AI-consent attachments are optional and not attached to the app version. |
| Purchase options | Both products allow multiseat purchases and list App Store, Apple Business and Apple School Manager. Organizational entitlement/redemption behavior was not verified; review this commercial setting before launch. No setting changed. |

## Rebuild and delivery

- Signed Release **1.0 (17)** archived and uploaded on 4 November at **22:37 CET**. Xcode reported **Upload succeeded**, **EXPORT SUCCEEDED**, and “Uploaded package is processing.” Archive guard verified production API, live Clerk, privacy URL, Apple-only sign-in and Sentry configuration.
- App, widget and WebRTC dSYMs uploaded successfully to Sentry with the existing authenticated CLI. Apple emitted a nonfatal warning that the third-party `Sentry.framework` dSYM is missing (UUID `761704F3-60F1-3BA4-B247-D08A8B5178EE`); this limits SDK-frame symbolication and did not prevent upload.
- Artifact: `/tmp/drillbit-appstore/1.0-17/Drillbit.xcarchive`. Logs: `/tmp/drillbit-review-20261104/`. Temporary local artifacts are not durable release storage.

## Verification boundaries

- Swift core: **58 tests passed**, 8 suites. No new simulator UI journey or physical-device run.
- Live production: `/health`, `/privacy`, `/support` returned **200**; unauthenticated `/v1/bootstrap` returned **401**. No paid model request, account mutation or purchase was triggered.
- Apple CLI has no configured API credentials; the signed-in browser and Xcode's existing account were used. No new credentials were created.
- Membership/capabilities, notification protocol version, bank/tax details beyond summary status and Sandbox tester inventory were not re-audited; the 1 November local report is historical evidence only.
