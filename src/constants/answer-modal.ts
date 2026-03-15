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
    "Design a distributed feature-flag platform for a large product organization that needs audit logs, staged rollout controls, low-latency SDK evaluation, environment isolation, emergency kill switches, and safe rollback behavior across web and mobile clients. Explain how you would separate the control plane from the data plane, handle rule propagation, support percentage rollouts and targeting, and keep evaluation reliable during outages or partial config delivery.",
  topic: "system design",
  difficulty: "medium",
} as const;

export const ANSWER_MODAL_MODEL_OPTIONS = [
  {
    value: "gpt 5.4",
    description: "Strong reasoning and polished structured answers.",
  },
  {
    value: "opus 4.6",
    description: "High depth for heavier multi-step design thinking.",
  },
  {
    value: "qwen 3.5 flash",
    description: "Fast, lightweight guidance for quick iteration.",
  },
] as const;

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
