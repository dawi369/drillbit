import type { AppContext, PromptContext } from "@/lib/storage/types";
import { SYSTEM_PROMPTS } from "@/lib/prompts/system-prompts";

export function buildPromptContext(appContext: AppContext): PromptContext | null {
  switch (appContext.kind) {
    case "generate":
      return {
        kind: "generate",
        systemPrompt: SYSTEM_PROMPTS.generate,
        focusPrompt: appContext.settings.focusPrompt,
        preferredDifficulty: appContext.settings.preferredDifficulty,
        blockedChallenges: appContext.runtime.blockedChallenges,
        memory: appContext.memory,
      };
    case "coach":
      if (!appContext.challenge) {
        return null;
      }

      if (appContext.challenge.mode === "solo") {
        return null;
      }

      return {
        kind: "coach",
        systemPrompt: SYSTEM_PROMPTS.coach,
        focusPrompt: appContext.settings.focusPrompt,
        preferredDifficulty: appContext.settings.preferredDifficulty,
        challenge: appContext.challenge,
        session: appContext.session,
        memory: appContext.memory,
      };
    case "reveal":
      if (!appContext.challenge) {
        return null;
      }

      if (appContext.challenge.mode === "solo") {
        return null;
      }

      return {
        kind: "reveal",
        systemPrompt: SYSTEM_PROMPTS.reveal,
        focusPrompt: appContext.settings.focusPrompt,
        preferredDifficulty: appContext.settings.preferredDifficulty,
        challenge: appContext.challenge,
        session: appContext.session,
        memory: appContext.memory,
      };
    case "summarize":
      if (!appContext.challenge) {
        return null;
      }

      return {
        kind: "summarize",
        systemPrompt: SYSTEM_PROMPTS.summarize,
        challenge: appContext.challenge,
        session: appContext.session,
        memory: appContext.memory,
      };
    default:
      return null;
  }
}

function renderSummaryList(title: string, items: string[]) {
  if (items.length === 0) {
    return `${title}: none`;
  }

  return `${title}:\n${items.map((item) => `- ${item}`).join("\n")}`;
}

export function renderPrompt(promptContext: PromptContext) {
  const baseMemorySections = [
    renderSummaryList(
      "recent summaries",
      promptContext.memory.recentSummaries.map(
        (summary) => `${summary.shortSummary} | feedback: ${summary.shortFeedback}`,
      ),
    ),
    renderSummaryList(
      "weak topic summaries",
      promptContext.memory.weakTopicSummaries.map(
        (summary) => `${summary.shortSummary} | weaknesses: ${summary.weaknesses.join(", ") || "none"}`,
      ),
    ),
  ];

  switch (promptContext.kind) {
    case "generate":
      return [
        promptContext.systemPrompt,
        `focus prompt:\n${promptContext.focusPrompt}`,
        `preferred difficulty: ${promptContext.preferredDifficulty ?? "unspecified"}`,
        renderSummaryList(
          "do not repeat these exact challenge shapes",
          promptContext.blockedChallenges.map((challenge) => challenge.summary),
        ),
        ...baseMemorySections,
      ].join("\n\n");
    case "coach":
    case "reveal":
      return [
        promptContext.systemPrompt,
        `focus prompt:\n${promptContext.focusPrompt}`,
        `preferred difficulty: ${promptContext.preferredDifficulty ?? "unspecified"}`,
        `challenge:\n- title: ${promptContext.challenge.title}\n- teaser: ${promptContext.challenge.teaser}\n- topic: ${promptContext.challenge.topic}\n- mode: ${promptContext.challenge.mode ?? "unspecified"}`,
        promptContext.session
          ? `session:\n- notes draft: ${promptContext.session.notesDraft ?? "none"}\n- conversation summary: ${promptContext.session.conversationSummary ?? "none"}`
          : "session:\n- none",
        ...baseMemorySections,
      ].join("\n\n");
    case "summarize":
      return [
        promptContext.systemPrompt,
        `challenge:\n- title: ${promptContext.challenge.title}\n- teaser: ${promptContext.challenge.teaser}\n- topic: ${promptContext.challenge.topic}`,
        promptContext.session
          ? `session:\n- notes draft: ${promptContext.session.notesDraft ?? "none"}\n- conversation summary: ${promptContext.session.conversationSummary ?? "none"}`
          : "session:\n- none",
        ...baseMemorySections,
      ].join("\n\n");
  }
}
