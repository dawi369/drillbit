import {
  parseCoachOutput,
  parseRevealOutput,
  parseSummarizeOutput,
} from "@/lib/ai/prompt-output";
import {
  createOpenRouterChatCompletion,
  streamOpenRouterChatCompletion,
} from "@/lib/ai/openrouter";
import { buildAppContext } from "@/lib/prompts/app-context";
import { buildPromptContext, renderPrompt } from "@/lib/prompts/prompt-context";
import { upsertChallengeSummary } from "@/lib/storage/repository";
import type { CoachTriggerReason } from "@/lib/storage/types";

async function runPromptKind(
  kind: "coach" | "reveal" | "summarize",
  challengeId: string,
  options?: {
    coachTrigger?: CoachTriggerReason;
    latestUserRequest?: string;
  },
) {
  const appContext = await buildAppContext({
    kind,
    challengeId,
    coachTrigger: options?.coachTrigger,
    latestUserRequest: options?.latestUserRequest,
  });
  const promptContext = buildPromptContext(appContext);

  if (!promptContext || !appContext.selectedModel) {
    throw new Error(`Unable to build ${kind} prompt context.`);
  }

  const renderedPrompt = renderPrompt(promptContext);
  const rawResponse = await createOpenRouterChatCompletion({
    model: appContext.selectedModel.remoteId,
    messages: [
      {
        role: "user",
        content: renderedPrompt,
      },
    ],
  });

  return {
    appContext,
    promptContext,
    renderedPrompt,
    rawResponse,
  };
}

export async function generateCoachGuidance(
  challengeId: string,
  options?: {
    coachTrigger?: CoachTriggerReason;
    latestUserRequest?: string;
  },
) {
  const result = await runPromptKind("coach", challengeId, options);

  return {
    ...result,
    output: parseCoachOutput(result.rawResponse),
  };
}

export async function streamCoachGuidance(
  challengeId: string,
  options?: {
    coachTrigger?: CoachTriggerReason;
    latestUserRequest?: string;
    onTextDelta?: (textDelta: string) => void;
  },
) {
  const appContext = await buildAppContext({
    kind: "coach",
    challengeId,
    coachTrigger: options?.coachTrigger,
    latestUserRequest: options?.latestUserRequest,
  });
  const promptContext = buildPromptContext(appContext);

  if (!promptContext || !appContext.selectedModel) {
    throw new Error("Unable to build coach prompt context.");
  }

  const renderedPrompt = renderPrompt(promptContext);
  const rawResponse = await streamOpenRouterChatCompletion({
    model: appContext.selectedModel.remoteId,
    messages: [
      {
        role: "user",
        content: renderedPrompt,
      },
    ],
    onTextDelta: options?.onTextDelta,
  });

  return {
    appContext,
    promptContext,
    renderedPrompt,
    rawResponse,
    output: parseCoachOutput(rawResponse),
  };
}

export async function generateRevealAnswer(challengeId: string) {
  const result = await runPromptKind("reveal", challengeId);

  return {
    ...result,
    output: parseRevealOutput(result.rawResponse),
  };
}

export async function streamRevealAnswer(
  challengeId: string,
  options?: {
    latestUserRequest?: string;
    onTextDelta?: (textDelta: string) => void;
  },
) {
  const appContext = await buildAppContext({
    kind: "reveal",
    challengeId,
    latestUserRequest: options?.latestUserRequest,
  });
  const promptContext = buildPromptContext(appContext);

  if (!promptContext || !appContext.selectedModel) {
    throw new Error("Unable to build reveal prompt context.");
  }

  const renderedPrompt = renderPrompt(promptContext);
  const rawResponse = await streamOpenRouterChatCompletion({
    model: appContext.selectedModel.remoteId,
    messages: [
      {
        role: "user",
        content: renderedPrompt,
      },
    ],
    onTextDelta: options?.onTextDelta,
  });

  return {
    appContext,
    promptContext,
    renderedPrompt,
    rawResponse,
    output: parseRevealOutput(rawResponse),
  };
}

export async function summarizeChallengeSession(challengeId: string) {
  const result = await runPromptKind("summarize", challengeId);
  const output = parseSummarizeOutput(result.rawResponse);
  const generatedAt = new Date().toISOString();

  await upsertChallengeSummary({
    id: challengeId,
    challengeId,
    shortSummary: output.shortSummary,
    shortFeedback: output.shortFeedback,
    strengths: output.strengths,
    weaknesses: output.weaknesses,
    tags: output.tags,
    completionScore: output.completionScore,
    generatedAt,
  });

  return {
    ...result,
    output,
  };
}
