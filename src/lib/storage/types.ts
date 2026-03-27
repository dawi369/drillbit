import type {
  Challenge,
  ChallengeDifficulty,
  ChallengeMode,
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

export type ChallengeConversationTurn = {
  id: string;
  role: "user" | "assistant";
  mode: Extract<ChallengeMode, "coach" | "reveal">;
  text: string;
  answer?: string;
  createdAt: string;
};

export type CoachTriggerReason =
  | "auto_initial"
  | "auto_after_progress"
  | "manual_request";

export type ChallengeSessionRecord = {
  challengeId: string;
  selectedMode?: ChallengeMode;
  notesDraft?: string;
  assistantDraft?: string;
  conversationHistory: ChallengeConversationTurn[];
  updatedAt: string;
};

export type ModelProvider =
  | "openrouter"
  | "openai"
  | "anthropic"
  | "ollama"
  | (string & {});

export type ModelRecord = {
  id: string;
  provider: ModelProvider;
  remoteId: string;
  label: string;
  isEnabled: boolean;
  isCustom: boolean;
  createdAt: string;
  updatedAt: string;
};

export type UserSettingsRecord = {
  id: "default";
  focusPrompt: string;
  preferredDifficulty?: ChallengeDifficulty;
  preferredMode?: ChallengeMode;
  notificationsEnabled?: boolean;
  selectedModelId?: string;
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

export type MemoryChallengeSummaryRow = ChallengeSummaryRecord & {
  challengeTitle: string;
  challengeTopic: string;
  challengeDifficulty?: ChallengeDifficulty;
};

export type MemoryTopicRollup = {
  topic: string;
  count: number;
  averageCompletionScore?: number;
  topStrengths: string[];
  topWeaknesses: string[];
};

export type MemoryOverview = {
  totalCompleted: number;
  averageCompletionScore?: number;
  strongestPatterns: string[];
  weakestPatterns: string[];
  recentSessions: MemoryChallengeSummaryRow[];
  topicRollups: MemoryTopicRollup[];
};

export type PromptKind = "generate" | "coach" | "reveal" | "summarize";

export type AppContext = {
  kind: PromptKind;
  settings: UserSettingsRecord;
  selectedModel?: ModelRecord;
  challenge?: ChallengeRecord;
  session?: ChallengeSessionRecord;
  runtime: {
    blockedChallenges: BlockedChallengeRecord[];
    coachTrigger?: CoachTriggerReason;
    latestUserRequest?: string;
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
      coachTrigger: CoachTriggerReason;
      latestUserRequest?: string;
      focusPrompt: string;
      preferredDifficulty?: ChallengeDifficulty;
      challenge: ChallengeRecord;
      session?: ChallengeSessionRecord;
      memory: AppContext["memory"];
    }
  | {
      kind: "reveal";
      systemPrompt: string;
      latestUserRequest?: string;
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

export function isValidChallengeCadenceHours(value: number): value is ChallengeCadenceHours {
  return ALLOWED_CHALLENGE_CADENCE_HOURS.includes(value as ChallengeCadenceHours);
}

export function isValidFirstChallengeTimeMinutes(value: number) {
  return Number.isInteger(value) && value >= 0 && value < 24 * 60;
}
