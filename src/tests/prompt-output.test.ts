import { describe, expect, test } from "bun:test";

import {
  parseCoachOutput,
  parseGenerateChallengeOutput,
  parseRevealOutput,
  parseSummarizeOutput,
} from "@/lib/ai/prompt-output";

describe("prompt output parsing", () => {
  test("parses challenge generation JSON", () => {
    const output = parseGenerateChallengeOutput(`{
      "title": "design reservation lock system",
      "teaser": "Design a reservation service with strict consistency under concurrent holds.",
      "topic": "backend"
    }`);

    expect(output).toEqual({
      title: "design reservation lock system",
      teaser: "Design a reservation service with strict consistency under concurrent holds.",
      topic: "backend",
    });
  });

  test("falls back to raw guidance text for coach output when JSON is missing", () => {
    const output = parseCoachOutput(
      "Focus on one exact failure path next: reservation succeeds, payment times out, hold expires, user retries.",
    );

    expect(output).toEqual({
      guidance:
        "Focus on one exact failure path next: reservation succeeds, payment times out, hold expires, user retries.",
    });
  });

  test("parses reveal output from plain text fallback by splitting guidance and answer", () => {
    const output = parseRevealOutput(
      "Start with the write path and source of truth.\n\n1. Use Postgres as the reservation authority.\n2. Treat cache as derived state.",
    );

    expect(output).toEqual({
      guidance: "Start with the write path and source of truth.",
      answer:
        "1. Use Postgres as the reservation authority.\n2. Treat cache as derived state.",
    });
  });

  test("parses summarize output and preserves normalized score", () => {
    const output = parseSummarizeOutput(`{
      "shortSummary": "Worked through a reservation lock backend.",
      "shortFeedback": "Good consistency instincts, but expiration handling stayed weak.",
      "strengths": ["consistency thinking", "service decomposition"],
      "weaknesses": ["expiration handling", "retry flow"],
      "tags": ["backend", "consistency"],
      "completionScore": 0.72
    }`);

    expect(output).toEqual({
      shortSummary: "Worked through a reservation lock backend.",
      shortFeedback:
        "Good consistency instincts, but expiration handling stayed weak.",
      strengths: ["consistency thinking", "service decomposition"],
      weaknesses: ["expiration handling", "retry flow"],
      tags: ["backend", "consistency"],
      completionScore: 0.72,
    });
  });
});
