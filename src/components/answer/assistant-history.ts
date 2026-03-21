import type { ChallengeConversationTurn } from "@/lib/storage/types";
import type { ChallengeMode } from "@/lib/widgets/types";

export type AssistantChatRole = Extract<ChallengeMode, "coach" | "reveal"> | "you";

export type AssistantChatMessage = {
  id: string;
  role: AssistantChatRole;
  text: string;
  isStreaming?: boolean;
};

export function mapConversationHistoryToChat(
  history: ChallengeConversationTurn[],
  mode: Extract<ChallengeMode, "coach" | "reveal">,
): AssistantChatMessage[] {
  return history
    .filter((turn) => turn.mode === mode)
    .map((turn) => ({
      id: turn.id,
      role: turn.role === "assistant" ? mode : ("you" as const),
      text: turn.text,
      isStreaming: false,
    }));
}

export function getLatestAssistantMessage(
  history: AssistantChatMessage[],
  mode: Extract<ChallengeMode, "coach" | "reveal">,
) {
  return [...history].reverse().find((message) => message.role === mode)?.text ?? null;
}
