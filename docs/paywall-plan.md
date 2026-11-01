# Paywall: how it works, what's free, what it costs, what to charge

Status 28 October 2026. Costs are **measured** where marked and **estimated** otherwise. The section 7 proposals were accepted; see section 8.

## 1. Why See Pro said "Subscription unavailable"

The app is fine: in the simulator, run from Xcode, the paywall shows both plans with prices. On a phone, StoreKit asks App Store Connect for `dawi.drillbit.pro.yearly` and `dawi.drillbit.pro.weekly`, and it got nothing back. One of these is missing, checked in this order:

1. **Agreements, Tax and Banking → Paid Apps agreement is *Active*.** It needs bank details and tax forms, and until it's active no product loads anywhere, sandbox included.
2. **Both subscriptions exist** with exactly those product IDs, inside the subscription group **Drillbit Pro**.
3. **Each is *Ready to Submit*:** a price for every territory, at least one localisation (display name and description), and a review screenshot. A subscription with *Missing Metadata* never loads.
4. **The phone is signed in to a Sandbox account:** Settings → Developer → Sandbox Apple Account. Development builds (from the Mac or `scripts/install-ios-device.sh`) and TestFlight builds buy in the sandbox.
5. **Wait.** New products can take up to an hour to show in the sandbox.

The paywall now checks for products before showing the store. If none come back, it says "Couldn't load Pro" and offers Try again, instead of StoreKit's bare message.

In the simulator, launch from Xcode (Product → Run). The Drillbit scheme attaches `Config/Drillbit.storekit`. A build installed any other way (`simctl install`) has no products and shows "Couldn't load Pro".

## 2. How it works

```text
Gate hit (server says no) → See Pro → Apple's subscription sheet (StoreKit)
   → purchase → signed transaction → POST /v1/entitlement → Worker verifies Apple's signature → plan = pro
Renewals, expiry, refunds → App Store Server Notifications v2 → POST /apple/notifications → entitlement updated
```

- **The server decides.** Every limit is enforced in the Worker (`plans.ts`, `practice-gate.ts`, `voice.ts`); the app only shows what the server says. A hacked app can't unlock Pro.
- **The paywall** is Apple's `SubscriptionStoreView` with our own header (Bit, one line, four perks) and plan picker: yearly first with "Save N%", weekly with its intro offer. It also carries Restore, Terms and Privacy, which App Review requires. Everything fits on one screen.

### Why not Superwall or RevenueCat (decided 28 October)

- **RevenueCat paywalls** only run on RevenueCat's purchase and entitlement layer. We already verify Apple's signed transactions on our own server, so adopting it means a second source of truth (or a migration) and a revenue share, all for a paywall template.
- **Superwall** is already wired in behind an empty `SUPERWALL_API_KEY`. Its value is A/B testing remote paywalls without a release, which needs real traffic to say anything. It also adds a third-party SDK to the privacy label, and a remote paywall that drops a required element is a common review rejection.
- **So:** ship the native paywall. Revisit Superwall once there are a few hundred paywall views a week to test against; turning it on is a key in `Production.xcconfig` plus dashboard setup (section 5 of app-store-readiness.md).
- **Plans are per account, not per device.** A subscription restored on a new phone attaches to whoever is signed in; it's refused if another Drillbit account already owns it.

## 3. What's free and what's Pro

| | Free | Pro |
|---|---|---|
| Questions (reps) | **2 in total** (since 31 Oct; was 3 a day). A rep skipped or swapped away before its 2nd message comes back. | Unlimited*, fair use 10 practised reps a day (since 1 Nov; was 30 questions written) |
| Inside a rep | 8 follow-ups, 2 nudges or examples | Unlimited |
| Voice | First 3 sessions, 3 min each, then one every 30 days | Unlimited*, fair use 60 min a day and **75 a week** (since 1 Nov; was 100, before that 150), up to 20 min a session |
| Feedback, Recall, Library | ✓ | ✓ |
| Daily question prepared for you | – | ✓ |
| Knowledge map and level estimate (Bit tab) | – | ✓ |

\* "Unlimited" is never shown with a number; hitting a fair-use cap says "that's a lot for one day, back tomorrow".

**New this pass:** a voice session counts only once you actually speak. Opening voice and going back to text without saying anything is free, however often you do it. The server refunds the session when it's confirmed closed with no speech from you. If the app dies mid-session, the session still counts, because more speech might have been in flight.

## 4. When we ask people to upgrade

1. **Home, once today's free reps are used:** "That's today's free reps… See Pro".
2. **Feedback screen after the last free rep of the day:** the same line with See Pro.
3. **Voice, once the free sessions are used:** a dialog with **See Pro** (gold) and Keep typing.
4. **Settings → Plan → See Pro**, any time.
5. **Inside a free rep:** running out of follow-ups or nudges shows See Pro instead of a dead Retry. That's the moment someone is most engaged.
6. **The Bit tab:** it's visible to everyone; on Free, tapping it opens the Pro screen ("See what you actually know.") and leaves you on your current tab.

There's no paywall at launch or during onboarding, and no nagging. Upgrades are offered only where a limit actually stopped someone.

## 5. What it costs us

### Measured

| Item | Cost | Source |
|---|---|---|
| A text interview (4–5 turns plus feedback) | **$0.0018–$0.0080, mean $0.0033** | 8 real runs, `scripts/evaluate-flow.ts`, 28 Oct, OpenRouter reported cost |
| Live voice (GPT-Live 1) | **$0.05 per minute the session is open**, billed per second, silence included | OpenAI model page |
| Voice reasoning hand-offs | about $0.0005 each (fast model) | same models as interview turns |

3 of 40 turns in that run came back as malformed JSON from the fast provider. The Worker retries these, but each retry is a paid call; worth watching in production.

### Budget figures used below (deliberately pessimistic)

- **Text rep: $0.01.** Three times the measured mean, covering longer real interviews, question generation, Recall cards and retries.
- **Voice: $0.055 per open minute**, including hand-offs.

### Per user per month

| Who | Usage | Cost per month |
|---|---|---|
| Free, typical | ~10 reps, 1 short voice session | ~$0.25 |
| Free, at every cap | 90 reps, 3 intro sessions then weekly tastes | ~$1.60 |
| Pro, text only | ~45 reps | ~$0.45 |
| Pro, prepping out loud | 3 × 25-min voice mocks a week (~325 min) | **~$18** |
| Pro, heavy voice | 45 min a day | **~$74** |
| Pro at today's fair-use ceiling | 20 × 20-min sessions a day | **~$660**: uncapped in practice |

**Voice is the business.** Text is so cheap it barely matters. Voice can cost more than any plan earns. Today's Pro fair-use cap of 20 sessions × 20 minutes a day is effectively no cap.

Fixed costs are small: Apple Developer $99 a year, Cloudflare Workers Paid $5 a month, Clerk free up to its MAU allowance, then per-user pricing. Check Clerk's current plan page.

## 6. What a subscriber is worth

Apple keeps **15%** if you enrol in the **App Store Small Business Program** (do this; it's free and takes effect from the next payout cycle) and **30%** if you don't.

| Plan | Price | You keep (15%) | Per month |
|---|---|---|---|
| Weekly (today) | $6.99 | $5.94 | ~$25.70 |
| Yearly (today) | $39.99 | $33.99 | **~$2.83** |
| Weekly intro week | $0.99 | $0.84 | – |

- **Weekly at $6.99** covers a "prepping out loud" user (~$18 a month), with a thin margin, and loses money on heavy voice users.
- **Yearly at $39.99 is underwater for anyone who uses voice regularly:** $33.99 a year buys about 620 voice minutes, roughly two weeks of real prep.
- The $0.99 intro week loses about $5 on someone who does three voice mocks in their first week. That's acceptable as acquisition only if a fair share renew.

## 7. Recommendation (*proposed*, needs your yes)

1. **Meter Pro voice in minutes, not sessions.** Proposed fair use: **60 minutes a day and 150 a week**, shown only when hit. Real prep (3–4 mocks a week) never touches it; abuse is capped at about $8 a week.
2. **End idle voice sessions automatically after 3 minutes without speech.** We pay for open minutes, not spoken ones.
3. **Prices:** Weekly **$7.99**, with the first week at $1.99, and Yearly **$79.99** ("Save 80%", about $6.67 a month). Prep is bursty: most yearly buyers do one or two intense stretches. At 150 minutes a week a yearly user still costs more than they pay, but that's the always-on edge case the weekly cap contains.
4. **Free voice:** keep the 3 intro sessions (the hook), but change the follow-up taste from **weekly to monthly**. It's the largest free cost line, and someone who wants voice every week is a Pro candidate.
5. **Keep text generous for free** (3 reps a day). It costs about a cent a rep, and it's what convinces people.
6. **Add See Pro to the in-rep limits** (section 4, item 5).
7. **Enrol in the Small Business Program** before the first sale.

### Rough monthly picture: 1,000 active users, 5% paying (illustrative only)

Assumes an average free user costs $0.40 a month today and $0.25 with a monthly taste, and an average Pro user ~$8 today and ~$7 with minute caps.

| | Today's prices and caps | Proposed |
|---|---|---|
| 950 free users | –$380 | –$240 (monthly taste) |
| 30 weekly subscribers | +$771 | +$883 |
| 20 yearly subscribers | +$57 | +$113 |
| 50 Pro users' AI cost (avg ~$8) | –$400 | –$350 (minute caps) |
| Fixed | –$40 | –$40 |
| **Net** | **≈ $0** | **≈ +$366** |

Conversion and usage are guesses until real numbers arrive. Every price and cap here is an environment variable or an App Store Connect setting, so they can move without a release, apart from new App Store prices for existing subscribers.

## 8. Decided 28 October

| | Decision | Where |
|---|---|---|
| Pro voice | 60 min a day and 150 min a rolling week; each session trimmed to what's left | `PRO_VOICE_MINUTES_PER_DAY`, `PRO_VOICE_MINUTES_PER_WEEK` |
| Idle voice | Ends after 3 minutes with no speech from either side, with a "Still there?" warning 30 s before | `LiveVoice.idleLimit` |
| Prices | Weekly $7.99 with the first week at $1.99, yearly $79.99 | App Store Connect (yours); `Config/Drillbit.storekit` matches |
| Free voice | 3 intro sessions, then one 3-minute taste every 30 days | `FREE_VOICE_TASTE_DAYS=30` |
| In-rep limits | Out of follow-ups or nudges shows See Pro instead of Retry | `InterviewView` |

Minutes come from the billed seconds the app reports when a session closes. A session that never reports counts as its full cap. A tampered app could under-report, but each session is still bounded by its server-issued cap.

## 9. Simulation — 31 October

`bun scripts/simulate-pricing.ts` simulates a month for a given number of active users and share on Pro. It writes the full tables to `.local/pricing-simulation.md`. Every price, cap, cost and behaviour assumption is a named constant at the top of the script.

**Measured inputs.** These come from production `ai_runs` and 15 synthetic interviews run today.
- Text rep: about $0.011 free, $0.013 Pro (longer reps). That covers question writing, the interview turns, nudges and feedback, plus a 10% allowance for retries.
- Voice: $0.051 per open minute.
- Clerk: free up to 50,000 monthly retained users.

**Per user per month.**

| | Cost | Apple pays out (15% cut, 3% refunds) |
|---|---|---|
| Free user (average) | $0.24 | – |
| Pro, text only / light voice / prepping out loud / heavy | $0.51 / $3.14 / $16.62 / $31.64 | – |
| Weekly subscriber (5-week average run, first week $1.99) | $11.68 | $24.24 |
| Yearly subscriber | $6.37 | **$5.50** |

**Monthly net (median)**

| Active users | 1% Pro | 2% | 3% | 5% | 8% | 10% |
|---|---|---|---|---|---|---|
| 1,000 | –$162 | –$105 | –$17 | +$104 | +$323 | +$489 |
| 10,000 | –$1,650 | –$942 | –$129 | +$1,371 | +$3,518 | +$5,045 |
| 100,000 | –$16,866 | –$9,488 | –$1,975 | +$12,720 | +$34,701 | +$50,673 |

**What it says**
- **Break-even is about 3.2% of active users on Pro** at any scale, and about 5% below a few hundred users, where the fixed costs dominate.
- Every 1% above break-even adds about $2,300 a month per 10,000 active users. Free users cost about $2,300 a month per 10,000, which is what that first 3% pays for.
- **Weekly carries the business; yearly at $79.99 loses a little.** A yearly subscriber keeps $5.50 a month but costs $6.37, because 150 minutes of voice a week is generous for that price. Pushing people towards yearly makes the month worse (–$1,436 at 70% yearly, against –$188 base).
- **Voice price is the biggest risk:** ±50% swings the 10,000-user, 3% case by about ±$1,800 a month. The Small Business Program is worth about $850 a month at that size.
- **Easy levers.** Each is an App Store or environment setting, so none needs a release. Yearly at $99.99 (–$18), Pro voice at 100 minutes a week (+$92), no monthly free voice taste (+$173), or both of the first two (+$335). If yearly subscribers sit idle half their months, as many do, yearly roughly breaks even by itself (+$201).

All of this is a model. Conversion, the weekly/yearly split, how long weekly subscribers stay, and voice minutes per subscriber should replace the assumptions as soon as there are real numbers.

## 10. Decided 31 October: two free reps, then Pro

| | Decision | Where |
|---|---|---|
| Free | **Two reps in total**, never refilled: onboarding's first, a second after exploring the app, then the paywall. Library and Recall stay open. | `FREE_REPS_LIFETIME=2` (production) |
| Entry offer | Keep the $1.99 first week (no free trial) | App Store Connect |
| Yearly | **$99.99** ("Save 75%", $8.33 a month) | App Store Connect (yours); `Config/Drillbit.storekit` matches |
| Pro voice | **100 minutes a week**, 60 a day | `PRO_VOICE_MINUTES_PER_WEEK=100` |

Why: subscription benchmarks (RevenueCat, State of Subscription Apps 2025) put download-to-paid at day 35 around **10–12% for hard paywalls against about 2% for freemium**, with one-year retention about the same (27% against 28%). Drillbit sells itself only after a rep or two, so the paywall waits until then rather than standing in front of everything. Each free person now costs about two text reps plus the voice intro, a few cents up to about $0.25, once, rather than every month.

Rough month one per 1,000 downloads, using the simulation's unit economics. A Pro subscriber nets about $7.45 a month after Apple and AI costs at the old prices, and **$9.05 at the new ones**. Yearly now earns its keep: it keeps $6.87 a month against $5.73 in costs, where it used to keep $5.50 against $6.37.

| | Paying | Cost of non-payers | Net |
|---|---|---|---|
| Freemium, 3 a day (before) | ~22 | ~500 active free users × $0.24 = –$120 | ≈ +$45 |
| Two free reps, then Pro (new prices) | ~100 (assumes 10%, the benchmark's lower end) | ~900 people × up to $0.25, once = –$225 at most | ≈ +$680 |

Watch: download-to-paid by day 35 (target 8% or more), App Store rating (paywalls can draw one-star reviews; the first rep has to land), and how many people finish rep two.

## 11. Launch economics — 1 November

`bun scripts/launch-economics.ts` works per cohort of downloads, because free users now cost money once rather than every month. Section 9's free-user figures model the older 3-a-day freemium. The script uses expected values, no randomness; every assumption is a named constant at the top, and the full tables go to `.local/launch-economics.md`. Unit costs are the 31 October measurements. Production had one day of traffic, so **usage, conversion and retention are assumptions**.

**What the caps allow** (updated for section 12's caps). A free download costs **$0.07** on average and **$0.49 at most**, once: two capped reps plus 9 intro voice minutes. A Pro user costs at most **$4.57 a week**, which is 10 reps a day plus 75 voice minutes; the rolling week allows up to $22 in a 30-day month. Voice at the weekly cap ($3.82) fits inside a full-price week ($6.59 kept). It doesn't fit inside yearly: $6.87 a month kept, against $16.56 a month for someone who sits on the cap every week.

**Expected use.** Assumed Pro months: text only 25 reps, $0.27; light 45 voice minutes, $2.51; prepping about three 20-minute mocks a week (280 minutes), $14.45; heavy, on the cap (325 minutes), $16.95. Weekly buyers are mid-prep, so they average **$8.41 a month**. Yearly buyers are idle about a third of their months and average **$3.58**. In the first year a new weekly buyer nets **$16.19** over about five weeks (45% stop after the $1.99 week), a yearly buyer nets **$39.44**, and the blend at 35% yearly is **$24.33**.

**Conversion scenarios, per 1,000 downloads.** "Expected" is 6% download-to-paid by day 35. RevenueCat's 2025 benchmarks put hard paywalls at about 10–12% and freemium at about 2%; two free reps sits between them, and education apps run below average.

| Download-to-paid | Paying | First-year net per 1,000 downloads | Month 12 at 1,000 downloads a month |
|---|---|---|---|
| 1% (very low) | 10 | +$173 | +$160 |
| 3% (low) | 30 | +$661 | +$648 |
| **6% (expected)** | 60 | **+$1,393** | **+$1,380** |
| 10% (high) | 100 | +$2,369 | +$2,356 |
| 15% (very high) | 150 | +$3,589 | +$3,576 |

Break-even is **0.3%** of downloads, or 2.0% if every non-payer used up the free voice intro. Year-two yearly renewals aren't counted. The month-12 column is before income tax and your own time.

**What moves it.**
- Without the Small Business Program, Apple keeps 30% and the blend drops to $16.14. Enrol before the first sale.
- Voice costing 50% more brings it to $13.69.
- If a third of every segment became heavy voice users, yearly would still earn $10.01 and the blend would be $12.40. At 100 minutes a week, yearly lost $5.93 in this case. If everyone were heavy, the business would still lose money (–$11.83 blended).
- Weekly buyers staying 14 full weeks instead of 7 brings the blend to $35.95.

**The remaining risk is yearly subscribers who use voice heavily.** If real data shows yearly voice minutes averaging above about 150 a month, give yearly its own weekly voice cap or raise the yearly price. Replace the assumptions with real numbers as soon as they exist: download-to-paid by day 35, the weekly/yearly split, how many stop after the $1.99 week, and voice minutes per subscriber-month by plan.

## 12. Decided 1 November: practised reps, refunds and 75 voice minutes

| | Decision | Where |
|---|---|---|
| What a rep is | A rep counts from the user's **second message**: typed answers and questions, or each thing they say in voice. Opening, browsing or rerolling a question isn't a rep. | `practisedAt` in `practice-gate.ts` |
| Pro reps | **10 practised a day** (UTC). Only starting a new rep checks it, so an open rep always finishes. Swapping a prepared question doesn't count. Developers are counted, never stopped. | `PRO_REPS_PER_DAY=10` |
| Pro question writing | **20 a day**, rerolls and abandoned questions included: a silent guard, about 4¢ at most | `PRO_GENERATIONS_PER_DAY=20` |
| Free refunds | A free rep that's **skipped or swapped away before its second message** comes back. Finishing one, even after one message, spends it. Deleting an unused one doesn't record it as spent. Free question writing stays capped at 10 a day. | `abandonedUnused` in `practice-gate.ts` |
| Pro voice | **75 minutes a week** for everyone, 60 a day, 20 a session: about three 20-minute mocks a week plus some slack | `PRO_VOICE_MINUTES_PER_WEEK=75` |

Hitting the Pro rep cap returns 429 `practice_limit` ("That's 10 reps today, which is plenty. More tomorrow."). Home then shows "Good day's work." with "Back tomorrow" instead of the failure ticket's Review. Text was never the cost, so the rep cap is about fair use and feel; the money is in voice. Section 11's numbers are rerun with these caps. A refunded free rep was used for at most one message, so refunds add well under a cent per download.

## 13. Business model review — 1 November

Two independent reviews: one rechecked the model and the enforced limits, the other researched pricing benchmarks. The arithmetic held. The model gained two corrections, and `.local/launch-economics.md` now shows Apple 15% and 30% side by side.

- **VAT.** EU/UK prices include VAT, and Apple removes it before its commission (Apple Schedule 2 §3.4(a)). The model now assumes 30% of sales in about-20%-VAT storefronts, which cuts proceeds by about 5%.
- **The free monthly voice taste never ends.** 5% of non-payers are assumed to come back each month, and the free worst case is $2.17 in the first year, not $0.49.

| First year, 35% yearly | Apple 15% | Apple 30% |
|---|---|---|
| Weekly / yearly / blended net per paying user | $14.84 / $35.32 / **$22.01** | $10.31 / $21.50 / **$14.23** |
| Per 1,000 downloads at 1% / 3% / **6%** / 10% / 15% | +$67 / +$510 / **+$1,175** / +$2,061 / +$3,169 | –$11 / +$277 / **+$708** / +$1,283 / +$2,002 |
| Break-even download-to-paid | 0.7% | 1.1% |

Benchmarks (RevenueCat State of Subscription Apps 2026): day-35 download-to-paid is 10.7% for hard paywalls, 2.1% for freemium, 3.1% for Education and 2.4% for AI apps. AI apps earn more per payer but churn faster (annual retention 21% against 31%). Plan against 3%, and treat 6% as the hopeful case.

Findings, ranked:

1. **Voice accounting trusts the app.** A session's minutes are the seconds the app reports at close (`voice.ts`), so a modified app could report one second and use about 400 minutes a day. A session closed with no user speech is waived and its start refunded, which can repeat without limit even from an unmodified app.
2. **The weekly plan carries regulatory and review risk.** The EU withdrawal-button rule (19 June 2026) and the UK DMCCA subscription regime (January 2027) both name discounted intros that renew into paid plans. App Review rejects intro prices shown louder than the real price. None of ten interview-prep competitors sells a recurring weekly plan. They use monthly or yearly plans and fixed passes; Hello Interview sells $47 for 1 month, $89 for 1 year and $299 lifetime.
3. **Yearly voice.** The break-even is about 132 voice minutes a month at 15% and 108 at 30%. The 75-minute weekly cap allows about 325.
4. **The free monthly taste** is the only free cost without an end.
5. **The refund rule** lets a free user take one interviewer reply per question, then skip, up to ten times a day.
6. **Smaller items:** cap the intro week's voice at 20 minutes (+$1.48 per subscriber); price EU/UK and large student markets for their actual proceeds and buying power; enrol in the Small Business Program (worth about $8 per subscriber).

## 14. Decided 1 November, after the review

| | Decision | Where |
|---|---|---|
| Free voice | **The 3 intro sessions only.** The monthly taste is off: after the intro sessions, voice is Pro. | `FREE_VOICE_TASTE_DAYS=0` (0 turns it off) |
| Free refunds | A free rep comes back only if it's skipped or swapped away **before the user's first message**. One message already earned an interviewer reply. | `abandonedUnused` in `practice-gate.ts` |
| Silent voice | **Two silent sessions a day are free**, and each refunds its start. After that a silent session counts like any other, because silence is billed. | `VOICE_FREE_LOOKS_PER_DAY` in `voice.ts` |
| Voice minutes | A close counts **at least the time from start to close**, up to the session's cap, whatever the app reports. | `voiceEvents` in `voice.ts` |
| Weekly plan | **Kept** ($7.99, first week $1.99), against the reviewers' advice. See below. | App Store Connect |

**Weekly, kept.** Apple allows weekly plans and intro prices, and plenty of top-grossing apps use them. Apple is the merchant of record and handles cancellation, refunds and renewal notices, which covers most of what the EU and UK subscription rules ask of the seller (not legal advice). The real risks are App Review's price-display rules and refund requests or one-star reviews from people surprised by the renewal. The paywall already leads with the full weekly price, and the intro reads "Try a week for $1.99, then $7.99 a week". Watch the refund rate and review mentions of "charged" in the first weeks. If either climbs, add a monthly plan next to weekly, which needs no migration.

With these changes (VAT included, no free taste), the expected 6% gives **+$1,254 per 1,000 downloads at Apple 15% and +$787 at 30%**. Break-even is 0.3% and 0.5%; it's 2.2% and 3.3% if every non-payer used every free voice minute.

**Known limit.** The server can't end a provider voice session. A modified app could close early in Drillbit's records and keep talking to the provider. Each start is still bounded by the provider's own session length and by 20 starts a day. Closing this needs a server-side hang-up or a provider-enforced session length, if the provider offers one.
