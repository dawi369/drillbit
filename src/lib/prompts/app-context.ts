import {
  ensureDefaultSettings,
  getChallengeById,
  getChallengeSession,
  getMostRecentResolvedChallenge,
  listBlockedChallenges,
  listChallengeSummaries,
  listSummariesByTopic,
} from "@/lib/storage/repository";
import type { AppContext, PromptKind } from "@/lib/storage/types";

type BuildAppContextOptions = {
  kind: PromptKind;
  challengeId?: string;
};

export async function buildAppContext({
  kind,
  challengeId,
}: BuildAppContextOptions): Promise<AppContext> {
  const settings = await ensureDefaultSettings();
  const challenge = challengeId ? await getChallengeById(challengeId) : null;
  const session = challenge ? await getChallengeSession(challenge.id) : null;
  const recentSummaries = await listChallengeSummaries(6);
  const lastResolvedChallenge = await getMostRecentResolvedChallenge();
  const focusTopic = challenge?.topic ?? lastResolvedChallenge?.topic;
  const weakTopicSummaries = focusTopic
    ? await listSummariesByTopic(focusTopic, 3)
    : [];
  const blockedChallenges = await listBlockedChallenges(365);

  return {
    kind,
    settings,
    challenge: challenge ?? undefined,
    session: session ?? undefined,
    runtime: {
      blockedChallenges,
    },
    memory: {
      recentSummaries,
      weakTopicSummaries,
      lastResolvedChallenge: lastResolvedChallenge ?? undefined,
    },
  };
}
