import type { AppContext, PromptContext } from "@/lib/storage/types";
import { getSystemPrompt } from "@/lib/prompts/prompt-library";

export function buildPromptContext(appContext: AppContext): PromptContext | null {
  switch (appContext.kind) {
    case "generate":
      return {
        kind: "generate",
        systemPrompt: getSystemPrompt("generate"),
        focusPrompt: appContext.settings.focusPrompt,
        preferredDifficulty: appContext.settings.preferredDifficulty,
        blockedChallenges: appContext.runtime.blockedChallenges,
        memory: appContext.memory,
      };
    case "coach":
      if (!appContext.challenge) {
        return null;
      }

      if (appContext.session?.selectedMode === "solo") {
        return null;
      }

      return {
        kind: "coach",
        systemPrompt: getSystemPrompt("coach"),
        coachTrigger: appContext.runtime.coachTrigger ?? "manual_request",
        latestUserRequest: appContext.runtime.latestUserRequest,
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

      if (appContext.session?.selectedMode === "solo") {
        return null;
      }

      return {
        kind: "reveal",
        systemPrompt: getSystemPrompt("reveal"),
        latestUserRequest: appContext.runtime.latestUserRequest,
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
        systemPrompt: getSystemPrompt("summarize"),
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
    return `<${title}>\nnone\n</${title}>`;
  }

  return `<${title}>\n${items.map((item) => `- ${item}`).join("\n")}\n</${title}>`;
}

function renderSection(tag: string, value: string) {
  return `<${tag}>\n${value}\n</${tag}>`;
}

function filterConversationHistoryByMode(
  history: AppContext["session"] extends infer T
    ? T extends { conversationHistory: infer H }
      ? H extends { role: string; mode: string; text: string; answer?: string }[]
        ? H
        : never
      : never
    : never,
  mode: "coach" | "reveal",
) {
  return history.filter((turn) => turn.mode === mode);
}

function renderConversationHistory(
  history: AppContext["session"] extends infer T
    ? T extends { conversationHistory: infer H }
      ? H extends { role: string; mode: string; text: string; answer?: string }[]
        ? H
        : never
      : never
    : never,
) {
  if (!history || history.length === 0) {
    return renderSection("conversation_history", "none");
  }

  return renderSection(
    "conversation_history",
    history
      .map((turn) => {
        const answerPart = turn.answer ? `\n- answer: ${turn.answer}` : "";
        return `- role: ${turn.role}\n- mode: ${turn.mode}\n- text: ${turn.text}${answerPart}`;
      })
      .join("\n\n"),
  );
}

export function renderPrompt(promptContext: PromptContext) {
  const baseMemorySections = [
    renderSummaryList(
      "recent_summaries",
      promptContext.memory.recentSummaries.map(
        (summary) => `${summary.shortSummary} | feedback: ${summary.shortFeedback}`,
      ),
    ),
    renderSummaryList(
      "weak_topic_summaries",
      promptContext.memory.weakTopicSummaries.map(
        (summary) => `${summary.shortSummary} | weaknesses: ${summary.weaknesses.join(", ") || "none"}`,
      ),
    ),
  ];

  switch (promptContext.kind) {
    case "generate":
      return [
        promptContext.systemPrompt,
        renderSection("focus_prompt", promptContext.focusPrompt),
        renderSection(
          "preferred_difficulty",
          promptContext.preferredDifficulty ?? "unspecified",
        ),
        renderSummaryList(
          "blocked_challenge_shapes",
          promptContext.blockedChallenges.map((challenge) => challenge.summary),
        ),
        ...baseMemorySections,
        renderSection(
          "task",
          "Generate one unique interview challenge as strict JSON with keys title, teaser, and topic.",
        ),
      ].join("\n\n");
    case "coach":
    case "reveal":
      const modeHistory = promptContext.session
        ? filterConversationHistoryByMode(promptContext.session.conversationHistory, promptContext.kind)
        : [];

      return [
        promptContext.systemPrompt,
        promptContext.kind === "coach"
          ? renderSection("coach_trigger", promptContext.coachTrigger)
          : null,
        promptContext.latestUserRequest
          ? renderSection(
              "latest_user_request",
              promptContext.latestUserRequest,
            )
          : null,
        renderSection("focus_prompt", promptContext.focusPrompt),
        renderSection(
          "preferred_difficulty",
          promptContext.preferredDifficulty ?? "unspecified",
        ),
        renderSection(
          "challenge",
          `- title: ${promptContext.challenge.title}\n- teaser: ${promptContext.challenge.teaser}\n- topic: ${promptContext.challenge.topic}\n- difficulty: ${promptContext.challenge.difficulty ?? "unspecified"}`,
        ),
        promptContext.session
          ? renderSection(
              "session",
              `- selected mode: ${promptContext.session.selectedMode ?? "unspecified"}\n- notes draft: ${promptContext.session.notesDraft ?? "none"}\n- assistant draft: ${promptContext.session.assistantDraft ?? "none"}`,
            )
          : renderSection("session", "none"),
        renderConversationHistory(modeHistory),
        ...baseMemorySections,
        renderSection(
          "task",
          promptContext.kind === "coach"
            ? "Respond as the coach with one very short hint or one short next-step question as strict JSON with key guidance."
            : "Reveal a strong structured answer for this challenge.",
        ),
      ]
        .filter(Boolean)
        .join("\n\n");
    case "summarize":
      return [
        promptContext.systemPrompt,
        renderSection(
          "challenge",
          `- title: ${promptContext.challenge.title}\n- teaser: ${promptContext.challenge.teaser}\n- topic: ${promptContext.challenge.topic}\n- difficulty: ${promptContext.challenge.difficulty ?? "unspecified"}`,
        ),
        promptContext.session
          ? renderSection(
              "session",
              `- selected mode: ${promptContext.session.selectedMode ?? "unspecified"}\n- notes draft: ${promptContext.session.notesDraft ?? "none"}\n- assistant draft: ${promptContext.session.assistantDraft ?? "none"}`,
            )
          : renderSection("session", "none"),
        promptContext.session
          ? renderConversationHistory(promptContext.session.conversationHistory)
          : renderSection("conversation_history", "none"),
        ...baseMemorySections,
        renderSection(
          "task",
          "Summarize this session as strict JSON with keys shortSummary, shortFeedback, strengths, weaknesses, tags, and completionScore.",
        ),
      ].join("\n\n");
  }
}
