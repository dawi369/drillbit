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
    value: "gpt",
    description: "GPT-4.5 - Strong reasoning and polished structured answers.",
  },
  {
    value: "opus",
    description:
      "Opus-4.6 - High depth for heavier multi-step design thinking.",
  },
  {
    value: "qwen",
    description:
      "Qwen-3.5 Flash - Fast, lightweight guidance for quick iteration.",
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

export const ANSWER_MODAL_PREVIEW_COACH_MESSAGES = [
  {
    id: "coach-1",
    role: "coach",
    text: "Start by separating the control plane from the data plane. Which one needs stronger consistency and which one needs lower latency?",
  },
  {
    id: "coach-2",
    role: "you",
    text: "I think the control plane needs stronger consistency, while the data plane should optimize for low-latency local evaluation.",
  },
  {
    id: "coach-3",
    role: "coach",
    text: "Good. Now pressure-test rule propagation: how do stale configs, rollout reversals, and offline SDKs affect the guarantees you can make?",
  },
  {
    id: "coach-4",
    role: "coach",
    text: "You should also explain how percentage rollouts are computed consistently across clients so two users do not bounce between variants unexpectedly.",
  },
] as const;
