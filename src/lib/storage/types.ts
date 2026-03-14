import type {
  Challenge,
  ChallengeDifficulty,
  ChallengeMode,
  ChallengeSkipReason,
  WidgetViewState,
} from "@/lib/widgets/types";

export const ALLOWED_CHALLENGE_CADENCE_HOURS = [1, 2, 3, 4, 6, 8, 12, 24] as const;

export type ChallengeCadenceHours = (typeof ALLOWED_CHALLENGE_CADENCE_HOURS)[number];

export type ChallengeRecord = Challenge & {
  createdAt: string;
  sourceModel?: string;
  sourcePromptVersion?: string;
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
  preferredMode?: ChallengeMode;
  defaultModel?: string;
  challengeCadenceHours?: ChallengeCadenceHours;
  firstChallengeTimeMinutes?: number;
  updatedAt: string;
};

export type WidgetSharedPayload = {
  version: 1;
  updatedAt: string;
  viewState: WidgetViewState;
};

export type BlockedChallengeRecord = {
  challengeId: string;
  summary: string;
  blockedAt: string;
  sourceLifecycle: "completed" | "skipped";
};

export type PromptKind = "generate" | "coach" | "reveal" | "summarize";

export type AppContext = {
  kind: PromptKind;
  settings: UserSettingsRecord;
  challenge?: ChallengeRecord;
  session?: ChallengeSessionRecord;
  runtime: {
    blockedChallenges: BlockedChallengeRecord[];
  };
  memory: {
    recentSummaries: ChallengeSummaryRecord[];
    weakTopicSummaries: ChallengeSummaryRecord[];
    lastResolvedChallenge?: ChallengeRecord;
  };
};

export type PromptContext =
  | {
      kind: "generate";
      systemPrompt: string;
      focusPrompt: string;
      preferredDifficulty?: ChallengeDifficulty;
      blockedChallenges: AppContext["runtime"]["blockedChallenges"];
      memory: AppContext["memory"];
    }
  | {
      kind: "coach";
      systemPrompt: string;
      focusPrompt: string;
      preferredDifficulty?: ChallengeDifficulty;
      challenge: ChallengeRecord;
      session?: ChallengeSessionRecord;
      memory: AppContext["memory"];
    }
  | {
      kind: "reveal";
      systemPrompt: string;
      focusPrompt: string;
      preferredDifficulty?: ChallengeDifficulty;
      challenge: ChallengeRecord;
      session?: ChallengeSessionRecord;
      memory: AppContext["memory"];
    }
  | {
      kind: "summarize";
      systemPrompt: string;
      challenge: ChallengeRecord;
      session?: ChallengeSessionRecord;
      memory: AppContext["memory"];
    };

export type ChallengeLifecycleRow = ChallengeRecord["lifecycle"];
export type ChallengeModeRow = ChallengeMode;
export type ChallengeSkipReasonRow = ChallengeSkipReason;

export function isValidChallengeCadenceHours(value: number): value is ChallengeCadenceHours {
  return ALLOWED_CHALLENGE_CADENCE_HOURS.includes(value as ChallengeCadenceHours);
}

export function isValidFirstChallengeTimeMinutes(value: number) {
  return Number.isInteger(value) && value >= 0 && value < 24 * 60;
}
