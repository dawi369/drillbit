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
- **The paywall** is Apple's `SubscriptionStoreView` with our plan picker: yearly first with "Save N%", weekly with its intro offer. It also carries Restore, Terms and Privacy, which App Review requires. Superwall is wired in but off; leave it off for launch.
- **Plans are per account, not per device.** A subscription restored on a new phone attaches to whoever is signed in; it's refused if another Drillbit account already owns it.

## 3. What's free and what's Pro

| | Free | Pro |
|---|---|---|
| Questions (reps) | 3 a day (resets at UTC midnight) | Unlimited*, fair-use 30 a day |
| Inside a rep | 8 follow-ups, 2 nudges or examples | Unlimited |
| Voice | First 3 sessions, 3 min each, then one every 30 days | Unlimited*, fair use 60 min a day and 150 a week, up to 20 min a session |
| Feedback, Recall, Library | ✓ | ✓ |
| Daily question prepared for you | – | ✓ |

\* "Unlimited" is never shown with a number; hitting a fair-use cap says "that's a lot for one day, back tomorrow".

**New this pass:** a voice session counts only once you actually speak. Opening voice and going back to text without saying anything is free, however often you do it. The server refunds the session when it's confirmed closed with no speech from you. If the app dies mid-session, the session still counts, because more speech might have been in flight.

## 4. When we ask people to upgrade

1. **Home, once today's free reps are used:** "That's today's free reps… See Pro".
2. **Feedback screen after the last free rep of the day:** the same line with See Pro.
3. **Voice, once the free sessions are used:** a dialog with **See Pro** (gold) and Keep typing.
4. **Settings → Plan → See Pro**, any time.
5. **Inside a free rep:** running out of follow-ups or nudges shows See Pro instead of a dead Retry. That's the moment someone is most engaged.

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
