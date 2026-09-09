import { describe, expect, test } from "bun:test";

import {
  getAssistantThreadMode,
  getAutoCoachTriggerReason,
  hasSessionSnapshotChanges,
  normalizeCoachText,
  resolveAnswerMode,
} from "@/components/answer/answer-flow";
import type { ChallengeConversationTurn } from "@/lib/storage/types";

describe("answer flow helpers", () => {
  test("resolves answer mode from route, session, then preference", () => {
    expect(
      resolveAnswerMode({
        routeMode: "reveal",
        sessionMode: "coach",
        preferredMode: "solo",
      }),
    ).toBe("reveal");

    expect(
      resolveAnswerMode({
        routeMode: null,
        sessionMode: "coach",
        preferredMode: "solo",
      }),
    ).toBe("coach");

    expect(
      resolveAnswerMode({
        routeMode: null,
        preferredMode: "solo",
      }),
    ).toBe("solo");
  });

  test("normalizes coach text and assistant thread mode", () => {
    expect(normalizeCoachText("  map   the   trade offs \n clearly  ")).toBe(
      "map the trade offs clearly",
    );
    expect(getAssistantThreadMode("solo")).toBe("coach");
    expect(getAssistantThreadMode("reveal")).toBe("reveal");
  });

  test("detects session snapshot changes only for the active challenge", () => {
    const history: ChallengeConversationTurn[] = [];
    const snapshot = {
      challengeId: "challenge-1",
      selectedMode: "coach" as const,
      notesDraft: "draft",
      assistantDraft: "",
      conversationHistory: history,
    };

    expect(hasSessionSnapshotChanges(snapshot, snapshot)).toBe(false);
    expect(
      hasSessionSnapshotChanges(snapshot, {
        ...snapshot,
        notesDraft: "",
      }),
    ).toBe(true);
    expect(
      hasSessionSnapshotChanges(snapshot, {
        ...snapshot,
        challengeId: "challenge-2",
      }),
    ).toBe(false);
  });

  test("gates auto coach until notes, progress, and cooldown conditions are met", () => {
    const baseArgs = {
      selectedMode: "coach" as const,
      resolvedChallengeId: "challenge-1",
      hasChallenge: true,
      isCoachLoading: false,
      normalizedNotesDraft: "a".repeat(130),
      conversationHistory: [] as ChallengeConversationTurn[],
      lastAutoCoachAt: null,
      lastAutoCoachNotesSnapshot: "",
      now: 20_000,
    };

    expect(getAutoCoachTriggerReason(baseArgs)).toBe("auto_initial");

    const history: ChallengeConversationTurn[] = [
      {
        id: "assistant-1",
        role: "assistant",
        mode: "coach",
        text: "push further",
        createdAt: new Date().toISOString(),
      },
    ];

    expect(
      getAutoCoachTriggerReason({
        ...baseArgs,
        conversationHistory: history,
        lastAutoCoachNotesSnapshot: "a".repeat(90),
      }),
    ).toBeNull();

    expect(
      getAutoCoachTriggerReason({
        ...baseArgs,
        conversationHistory: history,
        lastAutoCoachNotesSnapshot: "a".repeat(60),
      }),
    ).toBe("auto_after_progress");

    expect(
      getAutoCoachTriggerReason({
        ...baseArgs,
        lastAutoCoachAt: 10_000,
        now: 20_500,
      }),
    ).toBeNull();
  });
});
