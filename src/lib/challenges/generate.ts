import { buildAppContext } from "@/lib/prompts/app-context";
import { buildPromptContext, renderPrompt } from "@/lib/prompts/prompt-context";
import { createOpenRouterChatCompletion } from "@/lib/ai/openrouter";
import { parseGenerateChallengeOutput } from "@/lib/ai/prompt-output";
import {
  clearUnstartedReadyChallenges,
  getChallengeExpirationIso,
  upsertChallenge,
} from "@/lib/storage/repository";
import type { ChallengeRecord } from "@/lib/storage/types";
import type { ChallengeDifficulty } from "@/lib/widgets/types";

function createChallengeId() {
  return `challenge-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

function normalizeDifficulty(value: string | undefined): ChallengeDifficulty {
  if (value === "easy" || value === "hard") {
    return value;
  }

  return "medium";
}

export async function generateChallenge() {
  const appContext = await buildAppContext({ kind: "generate" });
  const promptContext = buildPromptContext(appContext);

  if (!promptContext || !appContext.selectedModel) {
    throw new Error("No selected model is configured for challenge generation.");
  }

  const renderedPrompt = renderPrompt(promptContext);
  const responseText = await createOpenRouterChatCompletion({
    model: appContext.selectedModel.remoteId,
    messages: [
      {
        role: "user",
        content: renderedPrompt,
      },
    ],
  });

  const parsed = parseGenerateChallengeOutput(responseText);
  await clearUnstartedReadyChallenges();

  const now = new Date().toISOString();
  const record: ChallengeRecord = {
    id: createChallengeId(),
    title: parsed.title.trim(),
    teaser: parsed.teaser.trim(),
    topic: parsed.topic.trim(),
    difficulty: normalizeDifficulty(appContext.settings.preferredDifficulty),
    lifecycle: "ready",
    createdAt: now,
    expiresAt: getChallengeExpirationIso(appContext.settings, new Date(now)),
    sourceModel: appContext.selectedModel.remoteId,
    sourcePromptVersion: "generate-v1",
  };

  await upsertChallenge(record);

  return {
    challenge: record,
    renderedPrompt,
    rawResponse: responseText,
  };
}
