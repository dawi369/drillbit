import { describe, expect, test } from "bun:test";

import {
  fromChallengeSessionRow,
  fromChallengeSummaryRow,
  parseJsonArray,
} from "@/lib/storage/mappers";

describe("storage mappers", () => {
  test("falls back to an empty string array when stored JSON is invalid", () => {
    expect(parseJsonArray("not json")).toEqual([]);
    expect(parseJsonArray(JSON.stringify(["solid", 123, "specific"]))).toEqual([
      "solid",
      "specific",
    ]);
  });

  test("keeps corrupted summary JSON from crashing memory reads", () => {
    const summary = fromChallengeSummaryRow({
      id: "summary-1",
      challenge_id: "challenge-1",
      short_summary: "summary",
      short_feedback: "feedback",
      strengths_json: "not json",
      weaknesses_json: JSON.stringify(["gap"]),
      tags_json: "{",
      completion_score: null,
      generated_at: "2026-05-24T00:00:00.000Z",
    });

    expect(summary.strengths).toEqual([]);
    expect(summary.weaknesses).toEqual(["gap"]);
    expect(summary.tags).toEqual([]);
  });

  test("keeps corrupted session history from crashing answer reads", () => {
    const session = fromChallengeSessionRow({
      challenge_id: "challenge-1",
      selected_mode: "coach",
      notes_draft: "notes",
      assistant_draft: "draft",
      conversation_history_json: "{",
      updated_at: "2026-05-24T00:00:00.000Z",
    });

    expect(session.conversationHistory).toEqual([]);
  });
});
