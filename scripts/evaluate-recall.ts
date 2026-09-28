/** Synthetic Recall-card and quote evaluation; never reads private practice records. The full run goes to .local/. */
import { mkdirSync, writeFileSync } from "node:fs";
import { messagesFor } from "../apps/api/src/ai";
import { reflectionOutputFor } from "../apps/api/src/domain";
import { groundReflection } from "../apps/api/src/learning";
import { pooled, structuredCall } from "./openrouter";

type Mode = "learn_together" | "coach_me" | "mock_interview";
type Turn = { prompt: string; answer: string; reply?: string } | { voice: [speaker: "user" | "assistant", text: string][] };
type Case = { name: string; mode: Mode; level: string; title: string; prompt: string; concepts: string[]; turns: Turn[]; help?: { body: string }[]; social?: boolean };

const cases: Case[] = [
  { name: "webhooks", mode: "coach_me", level: "mid", title: "Webhooks that land once", concepts: ["retry-safety", "queues"],
    prompt: "Your app sends webhooks to thousands of customer servers. Some are slow, some are down, and some reply 200 right before they crash.\n\n• About 2k events a second at peak\n• Receivers time out after 10s\n• Customers can replay events from a dashboard\n\nDesign delivery so every event lands once, even when things go sideways.",
    turns: [
      { prompt: "Design delivery so every event lands once.", answer: "A queue per customer, workers that POST each event, and a retry when a delivery fails.", reply: "Okay. The receiver timed out, but it already processed the event. Now what?" },
      { prompt: "The receiver timed out, but it already processed the event. Now what?", answer: "I'd send an idempotency key with every delivery so the receiver can drop repeats. And we retry right away until it works.", reply: "What happens to your queue if one customer's endpoint is down for an hour?" },
      { prompt: "What happens to your queue if one customer's endpoint is down for an hour?", answer: "We keep retrying, it'll recover eventually.", reply: "Fair. Let's wrap there." },
    ] },
  { name: "rate-limiter", mode: "coach_me", level: "mid", title: "Rate limiter for a public API", concepts: ["rate-limiting"],
    prompt: "A public API needs per-key limits so one noisy client can't starve the rest.\n\n• 12 API servers behind a load balancer\n• Limit is 100 requests a minute per key, bursts allowed\n• Redis is already in the stack\n\nWhere does the limit live, and how does it stay correct across servers?",
    turns: [
      { prompt: "Where does the limit live?", answer: "Token bucket per API key, refilled every second, stored in Redis so every server sees the same count.", reply: "How do two servers avoid both spending the last token?" },
      { prompt: "How do two servers avoid both spending the last token?", answer: "The check and decrement happen in one Lua script, so Redis runs them atomically.", reply: "Nice. What if Redis is unreachable?" },
      { prompt: "What if Redis is unreachable?", answer: "Then we just reject everything to be safe.", reply: "Okay." },
    ] },
  { name: "cache-stampede", mode: "coach_me", level: "junior", title: "A profile cache that survives expiry", concepts: ["caching", "backpressure"],
    prompt: "A profile cache sits in front of your database.\n\n• Entries live for ttl = 300 seconds\n• The database handles 2,000 reads per second\n• A popular profile expires and 500 requests miss at once\n\nWhat happens to the database, and how do you protect it?",
    turns: [{ prompt: "What happens to the database?", answer: "Cache profiles for 300 seconds. When one expires the requests go to the database and then we cache it again.", reply: "All 500 at the same moment?" },
      { prompt: "All 500 at the same moment?", answer: "Yeah I guess they all hit the database, it can take 2000 a second so it's fine.", reply: "Okay, let's stop there." }] },
  { name: "presence-mock", mode: "mock_interview", level: "senior", title: "Design chat presence", concepts: ["fault-tolerance", "coordination"],
    prompt: "Design the online presence indicator for a chat app.",
    turns: [
      { prompt: "Design the online presence indicator for a chat app.", answer: "Before I start: how many concurrent users, and how fresh does presence need to be?", reply: "About 10 million connected at peak. Within a minute is fine." },
      { prompt: "About 10 million connected at peak. Within a minute is fine.", answer: "Clients send a heartbeat every 30 seconds over the socket. Presence lives in Redis with a 70 second TTL, so you go offline after two missed heartbeats.", reply: "A gateway node dies with 200k sockets on it. What do their friends see?" },
      { prompt: "A gateway node dies with 200k sockets on it. What do their friends see?", answer: "They'd show online until the TTL runs out, then flip offline. When the users reconnect to another node they come back.", reply: "Good, that's the round." },
    ] },
  { name: "payments-guided", mode: "learn_together", level: "junior", title: "Charge a card exactly once", concepts: ["retry-safety", "transactions"],
    prompt: "Checkout calls a payment provider. Sometimes the call times out even though the charge went through.\n\n• The provider accepts an idempotency key header\n• Orders live in Postgres\n\nHow do you make sure a customer is charged exactly once?",
    help: [{ body: "One way in: what could the retry send so the provider recognises it?" }],
    turns: [
      { prompt: "How do you make sure a customer is charged exactly once?", answer: "Maybe retry the charge if it fails?", reply: "Close. If the first attempt actually succeeded, what stops the retry charging again?" },
      { prompt: "If the first attempt actually succeeded, what stops the retry charging again?", answer: "We send the same idempotency key, the order id, so the provider returns the first charge.", reply: "Exactly. Where do you record that the charge happened?" },
      { prompt: "Where do you record that the charge happened?", answer: "Save the charge id on the order row in the same transaction that marks it paid.", reply: "That's the core of it." },
    ] },
  { name: "feed-staff", mode: "coach_me", level: "staff", title: "A feed that survives launch day", concepts: ["partitioning", "capacity-planning"],
    prompt: "A social app's home feed is built by fanning posts out to followers. A few accounts have tens of millions of followers.\n\n• Most accounts have under 500 followers\n• Two teams own posting and feed reading separately\n\nHow do you build the feed so celebrity posts don't melt the write path?",
    turns: [{ prompt: "How do you build the feed?", answer: "Fan-out on write for most people, on read for accounts over a million followers, merged when the feed is fetched.", reply: "Which team owns the merge, and how do you roll it out?" },
      { prompt: "Which team owns the merge, and how do you roll it out?", answer: "Feed reading owns it. We shadow the merged read for a week and compare before switching.", reply: "Solid." }] },
  { name: "voice-queue", mode: "coach_me", level: "mid", title: "Resize images without losing jobs", concepts: ["queues", "fault-tolerance"],
    prompt: "Users upload photos and you create three thumbnail sizes in the background.\n\n• About 50 uploads a second\n• Workers sometimes crash mid-resize\n\nHow do jobs survive a worker crash?",
    turns: [{ voice: [["assistant", "How do jobs survive a worker crash?"], ["user", "So I'd put each upload on a queue and the worker only acks the message after all three thumbnails are written."], ["assistant", "And if it crashes after writing two?"], ["user", "The message comes back after the visibility timeout and another worker redoes it, and writing a thumbnail twice is fine because it just overwrites the same key."]] }] },
  { name: "thin", mode: "coach_me", level: "mid", title: "Webhooks that land once", concepts: ["retry-safety"],
    prompt: "Design webhook delivery so every event lands once.", turns: [{ prompt: "Design webhook delivery so every event lands once.", answer: "I'd use a queue.", reply: "Say more?" }] },
  { name: "social-only", mode: "coach_me", level: "mid", title: "Webhooks that land once", concepts: ["retry-safety"], social: true,
    prompt: "Design webhook delivery so every event lands once.", turns: [{ prompt: "Design webhook delivery so every event lands once.", answer: "hey! nice to meet you, just trying this out", reply: "Hey! Happy to. Whenever you're ready, where would you start?" }] },
];

function context(c: Case) {
  return {
    question: { title: c.title, prompt: c.prompt, conceptIds: c.concepts, primaryConceptId: c.concepts[0], engineeringLevel: c.level, guidanceMode: c.mode, constraints: [] },
    interview: c.turns.map(t => "voice" in t
      ? { kind: "voice", prompt: "", answer: "", result: null, delivery: "unknown", voice: t.voice.map(([speaker, text]) => ({ speaker, text })) }
      : { kind: "answer", prompt: t.prompt, answer: t.answer, result: t.reply ? { text: t.reply } : null, delivery: "unknown", voice: [] }),
    session: { answer: "", revision: 0 }, help: c.help ?? [], turns: [], adoptions: [], deliveryReceipts: [], exampleViewed: false,
    guidanceMode: c.mode, ...(c.mode === "mock_interview" ? { timing: { limitMinutes: 35, elapsedMinutes: 24 } } : {}),
  };
}

const banned = /^(why did you|what would you change|explain your|how did you|describe your)/i;
const words = (text: string) => new Set(text.toLowerCase().match(/[a-z0-9]{4,}/g) ?? []);
const common = new Set(["what", "when", "does", "that", "with", "this", "your", "from", "have", "they", "them", "then", "will", "would", "happens", "happen", "each", "every", "into", "after", "before", "which", "there", "their", "about", "still", "gets", "what's"]);
function anchored(prompt: string, question: string) {
  const numbers = (prompt.match(/\d[\d,.]*/g) ?? []).some(n => question.includes(n));
  const shared = [...words(prompt)].filter(w => !common.has(w) && words(question).has(w));
  return { anchored: numbers || shared.length >= 2, shared };
}

const runs = await pooled(cases, 3, async c => {
  const ctx = context(c);
  const { value, cost, ms } = await structuredCall(messagesFor("summarize", ctx), reflectionOutputFor(c.mode), { effort: "low" });
  const grounded = groundReflection(value, ctx);
  const cards = (grounded.evidence ?? []).map(e => {
    const prompt = e.recall?.prompt ?? "", answer = e.recall?.answer ?? "";
    return { quote: e.quote, signal: e.signal, observation: e.observation, prompt, answer,
      promptLength: prompt.length, answerLength: answer.length, banned: banned.test(prompt), ...anchored(prompt, c.prompt) };
  });
  return { case: c.name, mode: c.mode, social: !!c.social, dropped: (value.evidence?.length ?? 0) - cards.length, cards, takeaway: grounded.takeaway, improve: grounded.improve, cost, ms };
});

let total = 0;
for (const run of runs) {
  total += run.cost;
  console.log(`\n■ ${run.case} (${run.mode}) · ${run.cards.length} card(s)${run.dropped ? ` · ${run.dropped} ungrounded quote(s) dropped` : ""} · ${run.ms} ms`);
  for (const card of run.cards) {
    const flags = [card.promptLength > 120 && "prompt>120", card.answerLength > 240 && "answer>240", card.banned && "about-the-person", !card.anchored && "unanchored"].filter(Boolean);
    console.log(`  “${card.quote}” [${card.signal}]\n  Q: ${card.prompt}\n  A: ${card.answer}${flags.length ? `\n  ⚑ ${flags.join(", ")}` : ""}`);
  }
  if (!run.cards.length) console.log(`  (no quote) takeaway: ${run.takeaway}`);
}
const technical = runs.filter(r => !r.social);
const cards = runs.flatMap(r => r.cards);
console.log(`\nQuote rate: ${technical.filter(r => r.cards.length).length}/${technical.length} technical sessions` +
  ` · anchored ${cards.filter(c => c.anchored).length}/${cards.length} · about-the-person ${cards.filter(c => c.banned).length}` +
  ` · too long ${cards.filter(c => c.promptLength > 120 || c.answerLength > 240).length} · social leaks ${runs.filter(r => r.social && r.cards.length).length} · cost $${total.toFixed(4)}`);
mkdirSync(".local", { recursive: true });
writeFileSync(`.local/recall-eval-${Date.now()}.json`, JSON.stringify(runs, null, 1));
