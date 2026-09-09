import { summarizeChallengeSession } from "@/lib/ai/prompt-runtime";
import { debugLog } from "@/lib/debug";
import { listCompletedChallengesMissingSummary } from "@/lib/storage/repository";
import type { ChallengeRecord } from "@/lib/storage/types";

let inFlightRepairPromise: Promise<number> | null = null;

type SummaryRepairDependencies = {
  listCompletedChallengesMissingSummary: (limit: number) => Promise<ChallengeRecord[]>;
  summarizeChallengeSession: (challengeId: string) => Promise<unknown>;
  debugLog: typeof debugLog;
};

const defaultDependencies: SummaryRepairDependencies = {
  listCompletedChallengesMissingSummary,
  summarizeChallengeSession,
  debugLog,
};

export async function retryMissingChallengeSummaries(
  limit: number = 2,
  dependencies: SummaryRepairDependencies = defaultDependencies,
) {
  if (inFlightRepairPromise) {
    return inFlightRepairPromise;
  }

  inFlightRepairPromise = (async () => {
    const pendingChallenges = await dependencies.listCompletedChallengesMissingSummary(limit);

    if (pendingChallenges.length === 0) {
      return 0;
    }

    dependencies.debugLog("memory", "retrying missing summaries", {
      challengeIds: pendingChallenges.map((challenge) => challenge.id),
    });

    let repairedCount = 0;

    for (const challenge of pendingChallenges) {
      try {
        await dependencies.summarizeChallengeSession(challenge.id);
        repairedCount += 1;
      } catch (error) {
        dependencies.debugLog("memory", "summary retry failed", {
          challengeId: challenge.id,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }

    return repairedCount;
  })();

  try {
    return await inFlightRepairPromise;
  } finally {
    inFlightRepairPromise = null;
  }
}
