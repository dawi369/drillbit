import type { ChallengeMode } from "@/lib/widgets/types";

export const ANSWER_MODAL_SESSION_FIELDS = [
  "selectedMode",
  "notesDraft",
  "conversationSummary",
  "updatedAt",
] as const;

export const ANSWER_MODAL_PREVIEW_CHALLENGE = {
  title: "design a feature-flag platform",
  teaser:
    "Design a distributed feature-flag platform with audit logs, rollout controls, low-latency evaluation, and safe rollback behavior.",
  topic: "system design",
  difficulty: "medium",
} as const;

export const ANSWER_MODAL_MODE_COPY: Record<
  ChallengeMode,
  {
    title: string;
    body: string;
  }
> = {
  solo: {
    title: "solo workspace",
    body: "Quiet solving mode. Keep thinking in your own notes and switch modes only when you want outside pressure or a direct answer.",
  },
  coach: {
    title: "coach panel",
    body: "Guided interview pressure lives here: probing follow-ups, trade-off pushes, and hint-style responses instead of spoilers.",
  },
  reveal: {
    title: "reveal panel",
    body: "A structured model answer lives here with architecture, trade-offs, alternatives, and common failure modes.",
  },
};
