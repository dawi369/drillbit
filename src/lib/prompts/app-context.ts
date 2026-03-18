import {
  ensureDefaultSettings,
  getChallengeById,
  getChallengeSession,
  getMostRecentResolvedChallenge,
  getSelectedModel,
  listBlockedChallenges,
  listChallengeSummaries,
  listSummariesByTopic,
} from "@/lib/storage/repository";
import type { AppContext, PromptKind } from "@/lib/storage/types";

type BuildAppContextOptions = {
  kind: PromptKind;
  challengeId?: string;
  coachTrigger?: AppContext["runtime"]["coachTrigger"];
  latestUserRequest?: string;
};

export async function buildAppContext({
  kind,
  challengeId,
  coachTrigger,
  latestUserRequest,
}: BuildAppContextOptions): Promise<AppContext> {
  const settings = await ensureDefaultSettings();
  const selectedModel = await getSelectedModel();
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
    selectedModel: selectedModel ?? undefined,
    challenge: challenge ?? undefined,
    session: session ?? undefined,
    runtime: {
      blockedChallenges,
      coachTrigger,
      latestUserRequest,
    },
    memory: {
      recentSummaries,
      weakTopicSummaries,
      lastResolvedChallenge: lastResolvedChallenge ?? undefined,
    },
  };
}
