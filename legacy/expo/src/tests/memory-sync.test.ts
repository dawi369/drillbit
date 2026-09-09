import { beforeEach, describe, expect, mock, test } from "bun:test";

import type { ChallengeRecord } from "@/lib/storage/types";

const state = {
  listCalls: 0,
  pendingChallenges: [] as ChallengeRecord[],
  summarizedIds: [] as string[],
  failedIds: new Set<string>(),
  delayPromise: null as Promise<void> | null,
};

function createChallenge(id: string): ChallengeRecord {
  return {
    id,
    title: `challenge ${id}`,
    teaser: "teaser",
    topic: "backend",
    difficulty: "medium",
    lifecycle: "completed",
    createdAt: "2026-03-27T00:00:00.000Z",
    completedAt: "2026-03-27T00:05:00.000Z",
  };
}

mock.module("@/lib/storage/repository", () => ({
  listCompletedChallengesMissingSummary: async () => [],
}));

mock.module("@/lib/ai/prompt-runtime", () => ({
  summarizeChallengeSession: async () => ({}),
}));

mock.module("@/lib/debug", () => ({
  debugLog: () => {},
}));

const { retryMissingChallengeSummaries } = await import("@/lib/memory-sync");

function createDependencies() {
  return {
    listCompletedChallengesMissingSummary: async (limit: number) => {
      state.listCalls += 1;
      return state.pendingChallenges.slice(0, limit);
    },
    summarizeChallengeSession: async (challengeId: string) => {
      if (state.delayPromise) {
        await state.delayPromise;
      }

      state.summarizedIds.push(challengeId);

      if (state.failedIds.has(challengeId)) {
        throw new Error(`failed ${challengeId}`);
      }

      return {
        challengeId,
      };
    },
    debugLog: () => {},
  };
}

beforeEach(() => {
  state.listCalls = 0;
  state.pendingChallenges = [];
  state.summarizedIds = [];
  state.failedIds = new Set<string>();
  state.delayPromise = null;
});

describe("retryMissingChallengeSummaries", () => {
  test("repairs each completed challenge missing a summary", async () => {
    state.pendingChallenges = [createChallenge("a"), createChallenge("b")];

    const repairedCount = await retryMissingChallengeSummaries(5, createDependencies());

    expect(repairedCount).toBe(2);
    expect(state.listCalls).toBe(1);
    expect(state.summarizedIds).toEqual(["a", "b"]);
  });

  test("continues when one summary repair fails", async () => {
    state.pendingChallenges = [createChallenge("a"), createChallenge("b")];
    state.failedIds = new Set(["a"]);

    const repairedCount = await retryMissingChallengeSummaries(5, createDependencies());

    expect(repairedCount).toBe(1);
    expect(state.summarizedIds).toEqual(["a", "b"]);
  });

  test("deduplicates concurrent repair passes", async () => {
    let releaseDelay!: () => void;
    state.pendingChallenges = [createChallenge("a")];
    state.delayPromise = new Promise<void>((resolve) => {
      releaseDelay = resolve;
    });

    const firstRun = retryMissingChallengeSummaries(5, createDependencies());
    const secondRun = retryMissingChallengeSummaries(5, createDependencies());

    releaseDelay();

    const [firstResult, secondResult] = await Promise.all([firstRun, secondRun]);

    expect(firstResult).toBe(1);
    expect(secondResult).toBe(1);
    expect(state.listCalls).toBe(1);
    expect(state.summarizedIds).toEqual(["a"]);
  });
});
