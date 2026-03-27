import { describe, expect, test } from "bun:test";

import { buildDailyReminderPlan } from "@/lib/notification-plan";
import type { ChallengeRecord, UserSettingsRecord } from "@/lib/storage/types";

function createSettings(
  overrides: Partial<UserSettingsRecord> = {},
): UserSettingsRecord {
  return {
    id: "default",
    focusPrompt: "",
    preferredDifficulty: "medium",
    preferredMode: "solo",
    notificationsEnabled: true,
    selectedModelId: "model-1",
    challengeCadenceHours: 24,
    firstChallengeTimeMinutes: 9 * 60,
    updatedAt: "2026-03-27T00:00:00.000Z",
    ...overrides,
  };
}

function createChallenge(
  lifecycle: ChallengeRecord["lifecycle"],
): ChallengeRecord {
  return {
    id: "challenge-1",
    title: "design reservation lock system",
    teaser: "Design a hold service.",
    topic: "backend",
    difficulty: "hard",
    lifecycle,
    createdAt: "2026-03-27T00:00:00.000Z",
  };
}

describe("buildDailyReminderPlan", () => {
  test("returns no reminder when notifications are disabled", () => {
    expect(
      buildDailyReminderPlan({
        settings: createSettings({ notificationsEnabled: false }),
      }),
    ).toBeNull();
  });

  test("returns no reminder while a challenge is already in progress", () => {
    expect(
      buildDailyReminderPlan({
        settings: createSettings(),
        activeChallenge: createChallenge("in_progress"),
      }),
    ).toBeNull();
  });

  test("builds a ready-challenge reminder at the first challenge time", () => {
    expect(
      buildDailyReminderPlan({
        settings: createSettings(),
        activeChallenge: createChallenge("ready"),
      }),
    ).toEqual({
      identifier: "daily-challenge-reminder",
      hour: 9,
      minute: 0,
      title: "today's drill is ready",
      body: "design reservation lock system",
    });
  });

  test("builds a generic daily reminder when there is no active challenge yet", () => {
    const plan = buildDailyReminderPlan({
      settings: createSettings({ firstChallengeTimeMinutes: 8 * 60 + 30 }),
    });

    expect(plan?.hour).toBe(8);
    expect(plan?.minute).toBe(30);
    expect(plan?.title).toBe("time for a drillbit rep");
    expect(plan?.body.includes("8:30 AM")).toBe(true);
  });
});
