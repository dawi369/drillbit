import { useCallback } from "react";
import { Alert } from "react-native";

import { streamRevealAnswer } from "@/lib/ai/prompt-runtime";
import { getRevealPreviewText } from "@/components/answer/use-assistant-field-state";
import type { ChallengeConversationTurn } from "@/lib/storage/types";

type CommitAssistantTurn = (args: {
  currentHistory: ChallengeConversationTurn[];
  mode: "coach" | "reveal";
  userText?: string;
  assistantText: string;
  assistantAnswer?: string;
}) => ChallengeConversationTurn[];

export function useAnswerActions({
  assistantMessage,
  canInteractWithChallenge,
  resolvedChallengeId,
  selectedMode,
  conversationHistory,
  requestCoachGuidance,
  persistSession,
  setAssistantHistory,
  setConversationHistory,
  setAssistantLoading,
  setAssistantMessage,
  mapConversationHistoryToChat,
  commitAssistantTurn,
  coachField,
  revealField,
}: {
  assistantMessage: string;
  canInteractWithChallenge: boolean;
  resolvedChallengeId: string | null;
  selectedMode: "solo" | "coach" | "reveal";
  conversationHistory: ChallengeConversationTurn[];
  requestCoachGuidance: (args: {
    trigger: "manual_request" | "auto_initial" | "auto_after_progress";
    latestUserRequest?: string;
    appendToHistory?: boolean;
    onPartialGuidance?: (partialText: string) => void;
  }) => Promise<{ output: { guidance: string } } | null>;
  persistSession: (overrides?: {
    conversationSummary?: string;
    conversationHistory?: ChallengeConversationTurn[];
  }) => Promise<void>;
  setAssistantHistory: React.Dispatch<
    React.SetStateAction<{ id: string; role: "coach" | "you"; text: string }[]>
  >;
  setConversationHistory: React.Dispatch<React.SetStateAction<ChallengeConversationTurn[]>>;
  setAssistantLoading: (value: boolean) => void;
  setAssistantMessage: (value: string) => void;
  mapConversationHistoryToChat: (
    history: ChallengeConversationTurn[],
  ) => { id: string; role: "coach" | "you"; text: string }[];
  commitAssistantTurn: CommitAssistantTurn;
  coachField: {
    fail: (message: string) => void;
  };
  revealField: {
    begin: () => void;
    streamRevealDraft: (rawText: string) => void;
    finish: (value: string, nextAnswer?: string | null) => void;
    fail: (message: string) => void;
  };
}) {
  const handleAssistantSubmit = useCallback(() => {
    void (async () => {
      const trimmed = assistantMessage.trim();

      if (!trimmed) {
        return;
      }

      setAssistantHistory((current) => [
        ...current,
        {
          id: `you-${Date.now()}`,
          role: "you" as const,
          text: trimmed,
        },
      ]);
      const streamingAssistantId = `assistant-stream-${Date.now()}`;
      setAssistantMessage("");
      setAssistantLoading(true);

      try {
        if (selectedMode === "reveal") {
          if (!canInteractWithChallenge || !resolvedChallengeId) {
            return;
          }

          revealField.begin();
          let streamedText = "";
          setAssistantHistory((current) => [
            ...current,
            {
              id: streamingAssistantId,
              role: "coach" as const,
              text: "",
            },
          ]);

          const result = await streamRevealAnswer(resolvedChallengeId, {
            onTextDelta: (textDelta) => {
              streamedText += textDelta;
              revealField.streamRevealDraft(streamedText);
              const previewText = getRevealPreviewText(streamedText);
              setAssistantHistory((current) =>
                current.map((message) =>
                  message.id === streamingAssistantId
                    ? {
                        ...message,
                        text: previewText,
                      }
                    : message,
                ),
              );
            },
          });
          revealField.finish(result.output.guidance, result.output.answer);
          const nextHistory = commitAssistantTurn({
            currentHistory: conversationHistory,
            mode: "reveal",
            userText: trimmed,
            assistantText: result.output.guidance,
            assistantAnswer: result.output.answer,
          });

          setConversationHistory(nextHistory);
          setAssistantHistory(mapConversationHistoryToChat(nextHistory));
          await persistSession({
            conversationSummary: trimmed,
            conversationHistory: nextHistory,
          });
          return;
        }

        if (!canInteractWithChallenge || !resolvedChallengeId) {
          return;
        }

        setAssistantHistory((current) => [
          ...current,
          {
            id: streamingAssistantId,
            role: "coach" as const,
            text: "",
          },
        ]);

        const result = await requestCoachGuidance({
          trigger: "manual_request",
          latestUserRequest: trimmed,
          onPartialGuidance: (partialText: string) => {
            setAssistantHistory((current) =>
              current.map((message) =>
                message.id === streamingAssistantId
                  ? {
                      ...message,
                      text: partialText,
                    }
                  : message,
              ),
            );
          },
        });

        if (!result) {
          return;
        }

        const nextHistory = commitAssistantTurn({
          currentHistory: conversationHistory,
          mode: "coach",
          userText: trimmed,
          assistantText: result.output.guidance,
        });

        setConversationHistory(nextHistory);
        setAssistantHistory(mapConversationHistoryToChat(nextHistory));
        await persistSession({
          conversationSummary: trimmed,
          conversationHistory: nextHistory,
        });
      } catch (error) {
        if (selectedMode === "coach") {
          coachField.fail(error instanceof Error ? error.message : "assistant request failed");
        } else if (selectedMode === "reveal") {
          revealField.fail(error instanceof Error ? error.message : "assistant request failed");
        }
        Alert.alert(
          "assistant failed",
          error instanceof Error ? error.message : "Unknown error",
        );
      } finally {
        setAssistantLoading(false);
      }
    })();
  }, [
    assistantMessage,
    canInteractWithChallenge,
    coachField,
    commitAssistantTurn,
    conversationHistory,
    mapConversationHistoryToChat,
    persistSession,
    requestCoachGuidance,
    resolvedChallengeId,
    revealField,
    selectedMode,
    setAssistantHistory,
    setAssistantLoading,
    setAssistantMessage,
    setConversationHistory,
  ]);

  return {
    handleAssistantSubmit,
  };
}
