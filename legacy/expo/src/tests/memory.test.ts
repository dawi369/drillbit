import { describe, expect, test } from "bun:test";

import {
  completionScoreToPercent,
  formatCompletionScore,
  getCompletionScoreBarPercent,
} from "@/lib/memory";

describe("memory score helpers", () => {
  test("formats normalized completion scores as percentages", () => {
    expect(completionScoreToPercent(0.67)).toBe(67);
    expect(formatCompletionScore(0.67)).toBe("67%");
  });

  test("falls back cleanly when score is absent", () => {
    expect(completionScoreToPercent(undefined)).toBeNull();
    expect(formatCompletionScore(undefined)).toBe("-");
    expect(getCompletionScoreBarPercent(undefined)).toBe(32);
  });

  test("keeps graph percentages in a visible bounded range", () => {
    expect(getCompletionScoreBarPercent(0.05)).toBe(20);
    expect(getCompletionScoreBarPercent(0.82)).toBe(82);
    expect(getCompletionScoreBarPercent(1.4)).toBe(100);
  });
});
