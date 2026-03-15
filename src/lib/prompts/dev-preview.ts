import { buildAppContext } from "@/lib/prompts/app-context";
import { buildPromptContext, renderPrompt } from "@/lib/prompts/prompt-context";
import type {
  ChallengeRecord,
  ChallengeSessionRecord,
  PromptKind,
} from "@/lib/storage/types";

function createPreviewChallenge(kind: PromptKind): ChallengeRecord {
  return {
    id: `dev-preview-${kind}`,
    title: "design a feature-flag platform",
    teaser: "Design a feature-flag system with safe rollout controls, auditability, and low-latency evaluation.",
    topic: "system design",
    difficulty: "medium",
    lifecycle: kind === "summarize" ? "completed" : "in_progress",
    createdAt: new Date().toISOString(),
    startedAt: new Date().toISOString(),
    completedAt: kind === "summarize" ? new Date().toISOString() : undefined,
    sourcePromptVersion: "dev-preview",
  };
}

function createPreviewSession(kind: PromptKind): ChallengeSessionRecord {
  return {
    challengeId: `dev-preview-${kind}`,
    selectedMode: kind === "reveal" ? "reveal" : "coach",
    notesDraft:
      "Need to reason about rule propagation, segment evaluation, caching, and safe rollback paths.",
    conversationSummary:
      kind === "summarize"
        ? "User covered config storage, rollout percentages, and event logging but was weak on consistency and cache invalidation."
        : "User is midway through the challenge and has outlined the control plane and SDK responsibilities.",
    conversationHistory:
      kind === "generate" || kind === "summarize"
        ? []
        : [
            {
              id: `assistant-${kind}-1`,
              role: "assistant",
              mode: kind === "reveal" ? "reveal" : "coach",
              text: "Start by separating the control plane from the data plane.",
              createdAt: new Date().toISOString(),
            },
            {
              id: `user-${kind}-1`,
              role: "user",
              mode: kind === "reveal" ? "reveal" : "coach",
              text: "I think the control plane needs stronger consistency.",
              createdAt: new Date().toISOString(),
            },
          ],
    updatedAt: new Date().toISOString(),
  };
}

export async function buildPromptPreviewChain(kind: PromptKind) {
  const baseAppContext = await buildAppContext({ kind });

  const appContext =
    kind === "generate"
      ? baseAppContext
      : {
          ...baseAppContext,
          challenge: createPreviewChallenge(kind),
          session: createPreviewSession(kind),
        };

  const promptContext = buildPromptContext(appContext);
  const renderedPrompt = promptContext ? renderPrompt(promptContext) : null;

  return {
    appContext,
    promptContext,
    renderedPrompt,
  };
}
