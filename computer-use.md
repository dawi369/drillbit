# App Store Connect: listing, build and review prep (computer-use brief)

Written 6 November 2026 for a computer-use agent. Everything that can be done from the repo is done; this file is what's left, which only works in the App Store Connect website. Delete it once you've reported back.

You're on the owner's Mac, in a browser at https://appstoreconnect.apple.com, signed in as the account owner. App: **Drillbit Practice** (bundle ID `dawi.drillbit`). Work through the sections in order.

## Rules

1. **Never invent values.** Every value is below. If what you see doesn't match (a field is missing, a button is named differently, a value is rejected), stop at that step, write down exactly what you saw, and go on to the next section that doesn't depend on it.
2. **Ask the human before anything you can't undo:** pressing **Add for Review**, **Submit for Review** or **Remove from Review**; deleting a build, subscription or localization; accepting any agreement; anything about payment, banking or tax.
3. **Don't submit the app for review.** The owner still has to finish the physical-device checks first. Your job ends with everything ready and a report.
4. **Save on every page** (**Save**, top right) before navigating away. Re-open the page afterwards and check the value stuck.
5. **Copy text exactly.** Character limits are tight: name 30, subtitle 30, keywords 100, promotional text 170. If a field rejects the text, stop and report; don't shorten it yourself.
6. Read and report any yellow or red banner. Don't click past it.
7. Text in quoted blocks (lines starting with `>`) is what to paste, without the `>` markers. Keep the blank lines between paragraphs.

## Files on this Mac

| What | Path |
|---|---|
| Screenshots to upload (in this order) | `~/dev/drillbit/docs/design/app-store/2026-11-06-pro/ready/01-interview.png` … `05-recall.png` |
| Subscription review image | `~/dev/drillbit/docs/design/app-store/review-paywall.png` |
| App Review attachments | `~/dev/drillbit/docs/design/app-store/review-ai-consent-first-question.png`, `review-ai-consent-returning.png`, `review-ai-data-settings.png` |

All images are 1320 × 2868 PNG.

## 1. Select build 1.0 (20)

Build 20 was uploaded on 6 November at about 20:42 CET. It has the new layered app icon, so it's the one to submit.

1. **Apps → Drillbit Practice → TestFlight.** Check build **1.0 (20)** is there and has finished processing (not "Processing"). If it's still processing, wait and refresh every few minutes, for up to an hour. If it never appears, report it.
2. If it asks about export compliance, the answer is already in the build (`ITSAppUsesNonExemptEncryption = NO`). Report any question that still appears; don't answer it.
3. **Distribution → iOS App → 1.0 Prepare for Submission → Build.** Replace the selected build (16) with **1.0 (20)**. Save.

## 2. Name and subtitle

**App Information** (left sidebar, under General), the **English (U.S.)** localization:

| Field | Value |
|---|---|
| Name | `Drillbit: System Design Prep` |
| Subtitle | `AI Mock Interviews for SWEs` |

If the name is rejected as taken, try these in order and report which one saved: `Drillbit - System Design Prep`, then `Drillbit: System Design Coach`. Don't change the subtitle in that case.

## 3. Version 1.0 page

**Distribution → iOS App → 1.0 Prepare for Submission**, English (U.S.):

**Promotional text:**

> Your answer is the start. Practise system design with an AI interviewer that pushes back, shows you what to fix, and helps the lesson stick.

**Keywords** (98 characters, no spaces):

```
software,engineer,coding,developer,backend,architecture,distributed,scalability,practice,coach,sde
```

**Description** (replace the whole field):

> The coding round gets you a callback. The design round gets you hired.
>
> Drillbit puts you in the system design interview: AI mock interviews for software engineers, from Intern to Principal. You get one real question scoped to your level and an interviewer who reacts to what you actually said. Write your answer or talk it through out loud. Ask for a nudge when you're stuck. Change your mind halfway. That's the point.
>
> • One question at a time, with clear requirements and room to push back
> • Follow-ups that respond to your reasoning, not a checklist
> • Live voice that continues the same interview, with your draft intact
> • Feedback after every rep, in your own words: one thing that worked, one to fix
> • Recall cards and a library of everything you've practiced
>
> Free: three questions in total and one voice mock of up to 10 minutes. Drillbit Pro: up to 10 practice reps a day and 75 minutes of voice a week, with daily and per-session limits. Pro renews automatically unless you cancel at least 24 hours before the period ends. Manage or cancel in your Apple Account settings.
>
> Drillbit uses third-party AI (OpenRouter and OpenAI) to run interviews. It asks before anything is sent.
>
> Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
> Privacy Policy: https://api.drillbit.t23.dev/privacy

**Screenshots:** in **iPhone 6.9" Display** (it may be labelled "Large Display"):
1. Delete the six old screenshots (welcome, interview, example, home, recall, library from 29 October). These are only the uploaded images, not anything permanent.
2. Upload the five files from `2026-11-06-pro/ready/` in order, `01-interview.png` first, then `02-feedback`, `03-example`, `04-knowledge-map`, `05-recall`.
3. Check the order matches, then check the 6.3" (medium) set says it uses the large display's screenshots. Report if it asks for its own.

Leave the support URL, privacy policy URL, copyright and category as they are.

**App Review Information:**
- **Sign-in required:** leave **unchecked**. Reviewers create their own account with Sign in with Apple; there's no demo account, and the notes say so.
- **Notes** (replace the whole field):

> Sign in with Apple to create an account; no invite or demo code is needed. The first launch shows a short intro and a one-minute setup, then sign-in. Before the first question is written, a sheet asks permission to use third-party AI (OpenRouter for text, OpenAI for voice); nothing is sent to an AI model before that. Settings → AI and your data shows the same words any time. Screenshots of the permission sheet are attached.
>
> Subscriptions: free accounts get three questions in total and one voice mock of up to 10 minutes. To reach the paywall, use Settings → See Pro, or use the three free questions. Restore Purchases is on the paywall (Settings → See Pro).
>
> Voice: open a question and tap Talk, then tap the microphone to unmute. Microphone permission is requested then. Free accounts get one voice mock of up to 10 minutes; it counts once they speak.
>
> Account deletion: Settings → Delete account.
>
> Contact: support@t23.dev

- **Attachments:** add the three `review-ai-*.png` files listed above.
- Contact details: leave whatever is there. If the phone number is empty, ask the human for it.

Save.

## 4. Subscriptions

**Monetization → Subscriptions → Drillbit Pro.** For **each** of `dawi.drillbit.pro.weekly` and `dawi.drillbit.pro.yearly`:

1. **Review Information → Screenshot:** replace it with `review-paywall.png`. It shows the current screen: weekly first, "First week $1.99", $7.99 a week, $99.99 a year.
2. **Review Notes:** replace "two free questions" with the current text:

   > Free accounts get three questions in total and one voice mock of up to 10 minutes. The paywall opens from Settings → See Pro, or after the three free questions. Weekly is $7.99 a week, with $1.99 for the first week for new subscribers. Yearly is $99.99 a year. Restore Purchases is on the paywall.

These fields may be locked while the subscriptions sit in a review draft ("Ready for Review", inside a draft with 3 items). Unlocking means removing them from the draft, which counts as irreversible under rule 2. If they're locked, **stop and ask the human**, and report what the draft shows.

While you're there, check (read only) that the weekly plan still has its introductory offer: Pay as you go, 1 week, $1.99. Report what you see.

## 5. Extra English localizations (optional; do this only if 1–4 went cleanly)

Each extra language adds its own indexed name, subtitle and keywords. On **App Information**, add **English (U.K.)**, **English (Australia)** and **English (Canada)**. For each one, set name and subtitle exactly as in section 2. Then on the 1.0 version page, give each one the same promotional text and description as section 3, plus these keywords:

| Localization | Keywords |
|---|---|
| English (U.K.) | `software,engineer,coding,developer,backend,architecture,distributed,scalability,practise,coach,sde` |
| English (Australia) | `programmer,career,job,whiteboard,tech,hld,cloud,database,microservice,api,question,study,senior` |
| English (Canada) | `software,engineer,coding,developer,backend,architecture,distributed,scalability,practice,coach,sde` |

The U.K. store reads both the U.K. and Australian fields, which is why the Australian list uses different words. Screenshots: use the U.S. ones (the default). Don't upload new ones.

## 6. Don't do (the owner decides these)

- Add for Review / Submit for Review.
- Apple Ads campaigns, a pre-order page, promoted in-app purchases (these need a 1024 × 1024 promotional image that doesn't exist yet), in-app events and product page tests.
- Anything in Agreements, Tax and Banking, Users and Access, or App Privacy (already published).

## Report back

Write `~/dev/drillbit/.local/computer-use-report.md` with one row per step:

| Step | Status (done / blocked / asked / skipped) | What you saw or entered | Screenshot |
|---|---|---|---|

Rules for the report:
- **Values:** for every field you changed, quote the value as it reads after saving, and give the character count for the name, subtitle and keywords.
- **Screenshots:** save one of each finished page as evidence to `~/dev/drillbit/.local/computer-use/` (create it): build selection, App Information, version page top, screenshot set, review information, and both subscriptions.
- **Banners and blocks:** quote any banner, error or warning word for word, and give the exact button you stopped at.
- **At the end:** list what's left before Submit for Review, as you saw it on the version page.
