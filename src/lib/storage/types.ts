import type {
  Challenge,
  ChallengeDifficulty,
  ChallengeMode,
  ChallengeSkipReason,
  WidgetViewState,
} from "@/lib/widgets/types";

export type ChallengeRecord = Challenge & {
  createdAt: string;
};

export type ChallengeSummaryRecord = {
  id: string;
  challengeId: string;
  shortSummary: string;
  shortFeedback: string;
  strengths: string[];
  weaknesses: string[];
  tags: string[];
  completionScore?: number;
  generatedAt: string;
};

export type ChallengeSessionRecord = {
  challengeId: string;
  selectedMode?: ChallengeMode;
  notesDraft?: string;
  conversationSummary?: string;
  updatedAt: string;
};

export type UserSettingsRecord = {
  id: "default";
  focusPrompt: string;
  preferredDifficulty?: ChallengeDifficulty;
  defaultMode?: ChallengeMode;
  defaultModel?: string;
  challengeCadenceHours?: number;
  widgetModeDefault?: ChallengeMode;
  updatedAt: string;
};

export type WidgetSharedPayload = {
  version: 1;
  updatedAt: string;
  viewState: WidgetViewState;
};

export type ModelCallKind = "generate" | "coach" | "reveal";

export type ModelCallContext = {
  kind: ModelCallKind;
  settings: UserSettingsRecord;
  challenge?: ChallengeRecord;
  session?: ChallengeSessionRecord;
  memory: {
    recentSummaries: ChallengeSummaryRecord[];
    weakTopicSummaries: ChallengeSummaryRecord[];
    excludedDedupeKeys: string[];
    lastResolvedChallenge?: ChallengeRecord;
  };
};

export type ChallengeLifecycleRow = ChallengeRecord["lifecycle"];
export type ChallengeModeRow = ChallengeMode;
export type ChallengeSkipReasonRow = ChallengeSkipReason;
