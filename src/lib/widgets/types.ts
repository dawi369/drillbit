export const CHALLENGE_LIFECYCLES = ["ready", "in_progress", "completed", "skipped"] as const;

export const CHALLENGE_MODES = ["solo", "coach", "reveal"] as const;

export const CHALLENGE_SKIP_REASONS = ["regenerated", "not_interested"] as const;

export const WIDGET_VIEW_STATES = [
  "unconfigured",
  "ready",
  "in_progress",
  "awaiting_next",
  "error",
] as const;

export const WIDGET_PENDING_ACTIONS = ["refreshing", "skipping"] as const;

export type ChallengeLifecycle = (typeof CHALLENGE_LIFECYCLES)[number];

export type ChallengeMode = (typeof CHALLENGE_MODES)[number];

export type ChallengeSkipReason = (typeof CHALLENGE_SKIP_REASONS)[number];

export type WidgetViewStatus = (typeof WIDGET_VIEW_STATES)[number];

export type WidgetPendingAction = (typeof WIDGET_PENDING_ACTIONS)[number];

export type ChallengeDifficulty = "easy" | "medium" | "hard";

export type Challenge = {
  id: string;
  title: string;
  teaser: string;
  topic: string;
  difficulty?: ChallengeDifficulty;
  lifecycle: ChallengeLifecycle;
  createdAt?: string;
  startedAt?: string;
  completedAt?: string;
  skippedAt?: string;
  skipReason?: ChallengeSkipReason;
  expiresAt?: string;
};

export type WidgetViewState =
  | {
      status: "unconfigured";
      title: string;
      detail: string;
      cta: string;
      pendingAction?: Extract<WidgetPendingAction, "refreshing">;
    }
  | {
      status: "ready";
      challenge: Challenge;
      preferredMode?: ChallengeMode;
      title: string;
      detail: string;
      cta: string;
      pendingAction?: WidgetPendingAction;
    }
  | {
      status: "in_progress";
      challenge: Challenge;
      preferredMode?: ChallengeMode;
      title: string;
      detail: string;
      cta: string;
      pendingAction?: Extract<WidgetPendingAction, "refreshing">;
    }
  | {
      status: "awaiting_next";
      title: string;
      detail: string;
      cta: string;
      lastResolvedChallenge?: Challenge;
      nextRefreshAt?: string;
      pendingAction?: Extract<WidgetPendingAction, "refreshing">;
    }
  | {
      status: "error";
      title: string;
      detail: string;
      cta: string;
      message: string;
    };

export function createPlaceholderWidgetState(): WidgetViewState {
  return {
    status: "ready",
    title: "System design warm-up",
    detail: "Design a feature-flag platform with safe rollout controls.",
    cta: "Open challenge",
    preferredMode: "coach",
    challenge: {
      id: "placeholder-system-design-warmup",
      title: "System design warm-up",
      teaser: "Design a feature-flag platform with safe rollout controls.",
      topic: "System design",
      difficulty: "medium",
      lifecycle: "ready",
      createdAt: new Date(0).toISOString(),
    },
  };
}
