import { expect, it } from "vitest";
import { plainDashes, plainDashesDeep } from "../src/ai";

it("turns em and en dashes between words into commas and ranges into hyphens", () => {
  expect(plainDashes("Good instinct — for this one the numbers are given.")).toBe("Good instinct, for this one the numbers are given.");
  expect(plainDashes("the thumbnail CPU is what pins it—so you add workers")).toBe("the thumbnail CPU is what pins it, so you add workers");
  expect(plainDashes("Careful — the key, not the bytes — dedupes it.")).toBe("Careful, the key, not the bytes, dedupes it.");
  expect(plainDashes("Retry 3–5 times, then give up.")).toBe("Retry 3-5 times, then give up.");
  expect(plainDashes("Pick one — .")).toBe("Pick one.");
  expect(plainDashes("Stop here —")).toBe("Stop here");
  expect(plainDashes("Plain sentence, with commas.")).toBe("Plain sentence, with commas.");
});

it("keeps raw JSON valid while it streams, escaped dashes included", () => {
  const raw = '{"move":"ask_one","text":"Good instinct \\u2014 why the queue?","parameters":[{"label":"Peak","value":"35/s"}]}';
  const clean = plainDashes(raw);
  expect(JSON.parse(clean)).toEqual({ move: "ask_one", text: "Good instinct, why the queue?", parameters: [{ label: "Peak", value: "35/s" }] });
  expect(plainDashes('{"a":"x — ","b":"y"}')).toBe('{"a":"x, ","b":"y"}');
});

it("cleans every model string but leaves the person's own quoted words alone", () => {
  const out = plainDashesDeep({ summary: "Solid start — mostly.", evidence: [{ quote: "I'd cache it — then expire", observation: "Cache first — then invalidate." }] });
  expect(out).toEqual({ summary: "Solid start, mostly.", evidence: [{ quote: "I'd cache it — then expire", observation: "Cache first, then invalidate." }] });
});
