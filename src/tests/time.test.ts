import { describe, expect, test } from "bun:test";

import { getNextScheduledChallengeDate } from "@/lib/time";

describe("getNextScheduledChallengeDate", () => {
  test("does not schedule challenges before the first morning slot", () => {
    const next = getNextScheduledChallengeDate({
      from: new Date("2026-03-28T00:30:00.000Z"),
      firstChallengeTimeMinutes: 9 * 60,
      challengeCadenceHours: 24,
    });

    expect(next.toISOString()).toBe("2026-03-28T09:00:00.000Z");
  });

  test("respects the morning boundary even with multi-slot cadence", () => {
    const next = getNextScheduledChallengeDate({
      from: new Date("2026-03-28T00:30:00.000Z"),
      firstChallengeTimeMinutes: 9 * 60,
      challengeCadenceHours: 6,
    });

    expect(next.toISOString()).toBe("2026-03-28T09:00:00.000Z");
  });

  test("continues same-day cadence after the first slot has passed", () => {
    const next = getNextScheduledChallengeDate({
      from: new Date("2026-03-28T09:30:00.000Z"),
      firstChallengeTimeMinutes: 9 * 60,
      challengeCadenceHours: 6,
    });

    expect(next.toISOString()).toBe("2026-03-28T15:00:00.000Z");
  });

  test("rolls to the next morning slot after the last same-day slot", () => {
    const next = getNextScheduledChallengeDate({
      from: new Date("2026-03-28T22:30:00.000Z"),
      firstChallengeTimeMinutes: 9 * 60,
      challengeCadenceHours: 6,
    });

    expect(next.toISOString()).toBe("2026-03-29T09:00:00.000Z");
  });
});
