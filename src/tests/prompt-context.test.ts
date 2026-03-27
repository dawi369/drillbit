import { describe, expect, mock, test } from "bun:test";

import type { AppContext } from "@/lib/storage/types";

mock.module("@/lib/prompts/prompt-library", () => ({
  getSystemPrompt: (kind: string) => `system:${kind}`,
}));

const { buildPromptContext, renderPrompt } = await import("@/lib/prompts/prompt-context");

function createBaseAppContext(): AppContext {
  return {
    kind: "coach",
    settings: {
      id: "default",
      focusPrompt: "backend systems with consistency and reliability trade-offs",
      preferredDifficulty: "medium",
      preferredMode: "solo",
      selectedModelId: "model-1",
      challengeCadenceHours: 24,
      firstChallengeTimeMinutes: 9 * 60,
      updatedAt: "2026-03-27T00:00:00.000Z",
    },
    selectedModel: {
      id: "model-1",
      provider: "openrouter",
      remoteId: "test/model",
      label: "Test Model",
      isEnabled: true,
      isCustom: false,
      createdAt: "2026-03-27T00:00:00.000Z",
      updatedAt: "2026-03-27T00:00:00.000Z",
    },
    challenge: {
      id: "challenge-1",
      title: "design reservation lock system",
      teaser: "Design a reservation hold backend with strict consistency.",
      topic: "backend",
      difficulty: "hard",
      lifecycle: "in_progress",
      createdAt: "2026-03-27T00:00:00.000Z",
    },
    session: {
      challengeId: "challenge-1",
      selectedMode: "coach",
      notesDraft: "gateway, reservation service, postgres, redis, expirations",
      assistantDraft: "",
      conversationHistory: [],
      updatedAt: "2026-03-27T00:01:00.000Z",
    },
    runtime: {
      blockedChallenges: [],
      coachTrigger: "manual_request",
    },
    memory: {
      recentSummaries: [],
      weakTopicSummaries: [],
    },
  };
}

describe("prompt context", () => {
  test("suppresses coach prompts when the session mode is solo", () => {
    const appContext = createBaseAppContext();
    appContext.kind = "coach";
    appContext.session = {
      ...appContext.session!,
      selectedMode: "solo",
    };

    const promptContext = buildPromptContext(appContext);

    expect(promptContext).toBeNull();
  });

  test("suppresses reveal prompts when the session mode is solo", () => {
    const appContext = createBaseAppContext();
    appContext.kind = "reveal";
    appContext.session = {
      ...appContext.session!,
      selectedMode: "solo",
    };

    const promptContext = buildPromptContext(appContext);

    expect(promptContext).toBeNull();
  });

  test("renders a more concrete generation task instruction", () => {
    const appContext: AppContext = {
      ...createBaseAppContext(),
      kind: "generate",
      challenge: undefined,
      session: undefined,
      runtime: {
        blockedChallenges: [],
      },
    };

    const promptContext = buildPromptContext(appContext);

    if (!promptContext || promptContext.kind !== "generate") {
      throw new Error("expected generate prompt context");
    }

    const prompt = renderPrompt(promptContext);

    expect(
      prompt.includes("The teaser should make the central task explicit"),
    ).toBe(true);
    expect(
      prompt.includes("specific constraints or failure pressure"),
    ).toBe(true);
  });
});
