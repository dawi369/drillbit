import type { Env } from "./platform";

// Public pages App Store Connect links to. Plain HTML so they render anywhere without a separate site.
// Keep these in step with PrivacyInfo.xcprivacy and the App Store privacy label.
const updated = "27 October 2026";

function escape(value: string) {
  return value.replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
}

function page(title: string, body: string) {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title} · Drillbit</title>
<style>
:root{color-scheme:light dark}
body{font:17px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;max-width:680px;margin:0 auto;padding:32px 20px 64px}
h1{font-size:28px;margin:0 0 4px}h2{font-size:20px;margin:32px 0 8px}
p,li{margin:8px 0}.muted{opacity:.7}a{color:#d97706}
</style></head><body>${body}</body></html>`;
}

function contact(env: Env) {
  const email = env.SUPPORT_EMAIL?.trim();
  return email && !email.startsWith("REPLACE")
    ? `<a href="mailto:${escape(email)}">${escape(email)}</a>`
    : "the contact address on our App Store listing";
}

export function privacyPolicy(env: Env) {
  return page("Privacy Policy", `
<h1>Privacy Policy</h1>
<p class="muted">Last updated ${updated}</p>
<p>Drillbit is a system design interview practice app. This policy explains what we collect, why, who processes it and the choices you have. Questions: ${contact(env)}.</p>

<h2>What we collect</h2>
<ul>
<li><strong>Account details.</strong> When you sign in with Apple, Google or GitHub, our sign-in provider gives us an account identifier and, if you share it, your email address.</li>
<li><strong>Practice content.</strong> Your answers, interview conversations, voice transcripts, feedback, practice history, learning plan and settings.</li>
<li><strong>Voice audio.</strong> When you use live voice, your microphone audio streams to our voice provider to run the conversation. We keep the text transcript, not the audio.</li>
<li><strong>Purchases.</strong> If you subscribe, Apple sends us a signed record of the subscription (product, transaction identifier, dates and status) so we can unlock Pro. We never see your payment details.</li>
<li><strong>Voice notes.</strong> If you send one from Settings → Feedback, we keep the recording with your account so the developer can listen to it. It isn't sent to any AI provider, and it's deleted with your account.</li>
<li><strong>Usage counts.</strong> How many questions and voice sessions you've used, so free and fair-use limits work.</li>
<li><strong>Your own provider key</strong>, if you add one in Settings. It's stored encrypted and only used for your requests.</li>
</ul>

<h2>How we use it</h2>
<p>Only to run Drillbit: generating questions, holding the interview, writing feedback, keeping your history, enforcing plan limits and verifying subscriptions. We don't sell your data, show ads, track you across other apps or websites, or use your content to train our own models.</p>

<h2>Third-party AI</h2>
<p>Drillbit asks for your permission before any of this happens. To reply to you, what you write is sent to AI models through <a href="https://openrouter.ai/privacy">OpenRouter</a>, which routes requests to model providers such as OpenAI and DeepSeek hosts. Live voice audio goes to <a href="https://openai.com/policies/privacy-policy/">OpenAI</a>. These providers process the content to produce a response under their own terms; we send only what the interview needs, not your email address.</p>

<h2>Other service providers</h2>
<ul>
<li><a href="https://clerk.com/legal/privacy">Clerk</a> handles sign-in.</li>
<li><a href="https://www.cloudflare.com/privacypolicy/">Cloudflare</a> hosts our servers and database.</li>
<li><a href="https://sentry.io/privacy/">Sentry</a> (EU data region) receives crash and error reports: the app version, device model and operating system, and where the code went wrong. Reports carry no account or device identifier, no location, and none of your answers, conversations or recordings. Bug reports you write in Settings → Feedback go to Sentry too, with the same app and device details and nothing else.</li>
<li>Apple processes purchases and subscriptions.</li>
<li>If we use <a href="https://superwall.com/privacy">Superwall</a> to show the subscription screen, it receives an anonymous account identifier and paywall interactions.</li>
</ul>

<h2>Retention and deletion</h2>
<p>We keep your data while your account exists. Delete your account any time in Settings → Delete account. That removes your practice data and sign-in account from our systems. Subscriptions are managed by Apple; cancel them in your Apple ID settings. AI providers may keep request data briefly under their own policies.</p>

<h2>Your rights</h2>
<p>You can access, correct, export or delete your data. Most of this is in the app; for anything else, contact us at ${contact(env)}. Depending on where you live (for example under the GDPR or CCPA) you may have additional rights, including complaining to your local data protection authority.</p>

<h2>Security</h2>
<p>Data travels over encrypted connections. Provider keys are encrypted at rest. No system is perfectly secure, but we limit access to what's needed to run the service.</p>

<h2>Children</h2>
<p>Drillbit isn't directed at children under 13 and we don't knowingly collect their data.</p>

<h2>Changes</h2>
<p>If this policy changes, we'll update the date above and, for meaningful changes, tell you in the app.</p>
`);
}

export function supportPage(env: Env) {
  return page("Support", `
<h1>Drillbit support</h1>
<p>Stuck, found a bug, or have a billing question? Email ${contact(env)} and say whether it happened on a phone or in voice.</p>
<h2>Subscriptions</h2>
<p>Manage or cancel Pro in Drillbit under Settings → Manage subscription, or in the Settings app → your name → Subscriptions. Restore a purchase on a new phone from Settings → Restore purchases. Refunds are handled by Apple at <a href="https://reportaproblem.apple.com">reportaproblem.apple.com</a>.</p>
<h2>Your data</h2>
<p>Delete your account and all practice data in Settings → Delete account. See the <a href="/privacy">privacy policy</a>.</p>
`);
}
