import { useCallback } from "react";
import { Alert } from "react-native";

import type { AssistantChatMessage } from "@/components/answer/assistant-history";
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
  setCoachLoading,
  setRevealLoading,
  setAssistantMessage,
  mapConversationHistoryToChat,
  commitAssistantTurn,
  coachField,
  revealField,
  beginRevealRequest,
  isRevealRequestCurrent,
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
    assistantDraft?: string;
    conversationHistory?: ChallengeConversationTurn[];
  }) => Promise<void>;
  setAssistantHistory: React.Dispatch<React.SetStateAction<AssistantChatMessage[]>>;
  setConversationHistory: React.Dispatch<React.SetStateAction<ChallengeConversationTurn[]>>;
  setCoachLoading: (value: boolean) => void;
  setRevealLoading: (value: boolean) => void;
  setAssistantMessage: (value: string) => void;
  mapConversationHistoryToChat: (
    history: ChallengeConversationTurn[],
  ) => AssistantChatMessage[];
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
  beginRevealRequest: () => number;
  isRevealRequestCurrent: (requestId: number) => boolean;
}) {
  const handleAssistantSubmit = useCallback(() => {
    void (async () => {
      const trimmed = assistantMessage.trim();

      if (!trimmed) {
        return;
      }

      const submittedAt = Date.now();
      const userMessageId = `you-${submittedAt}`;
      const streamingAssistantId = `assistant-stream-${submittedAt}`;
      const assistantRole = selectedMode === "reveal" ? ("reveal" as const) : ("coach" as const);

      setAssistantHistory((current) => [
        ...current,
        {
          id: userMessageId,
          role: "you" as const,
          text: trimmed,
        },
        {
          id: streamingAssistantId,
          role: assistantRole,
          text: "",
          isStreaming: true,
        },
      ]);

      setAssistantMessage("");
      let revealRequestId: number | null = null;

      try {
        if (selectedMode === "reveal") {
          if (!canInteractWithChallenge || !resolvedChallengeId) {
            return;
          }

          const requestId = beginRevealRequest();
          revealRequestId = requestId;
          setRevealLoading(true);
          revealField.begin();
          let streamedText = "";

          const result = await streamRevealAnswer(resolvedChallengeId, {
            latestUserRequest: trimmed,
            onTextDelta: (textDelta) => {
              if (!isRevealRequestCurrent(requestId)) {
                return;
              }

              streamedText += textDelta;
              revealField.streamRevealDraft(streamedText);
              const previewText = getRevealPreviewText(streamedText);
              setAssistantHistory((current) =>
                current.map((message) =>
                  message.id === streamingAssistantId
                    ? {
                        ...message,
                        text: previewText,
                        isStreaming: true,
                      }
                    : message,
                ),
              );
            },
          });

          if (!isRevealRequestCurrent(requestId)) {
            return;
          }

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
          await persistSession({ assistantDraft: "", conversationHistory: nextHistory });
          return;
        }

        if (!canInteractWithChallenge || !resolvedChallengeId) {
          return;
        }

        setCoachLoading(true);
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
                      isStreaming: true,
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
        await persistSession({ assistantDraft: "", conversationHistory: nextHistory });
      } catch (error) {
        const errorMessage =
          error instanceof Error ? error.message : "assistant request failed";

        if (
          selectedMode === "reveal" &&
          revealRequestId != null &&
          !isRevealRequestCurrent(revealRequestId)
        ) {
          return;
        }

        setAssistantHistory((current) =>
          current.map((message) =>
            message.id === streamingAssistantId
              ? {
                  ...message,
                  text: errorMessage,
                  isStreaming: false,
                }
              : message,
          ),
        );

        if (selectedMode === "coach") {
          coachField.fail(errorMessage);
        } else if (selectedMode === "reveal") {
          if (revealRequestId != null && isRevealRequestCurrent(revealRequestId)) {
            revealField.fail(errorMessage);
          }
        }
        Alert.alert("assistant failed", errorMessage);
      } finally {
        if (selectedMode === "coach") {
          setCoachLoading(false);
        } else if (
          selectedMode === "reveal" &&
          revealRequestId != null &&
          isRevealRequestCurrent(revealRequestId)
        ) {
          setRevealLoading(false);
        }
      }
    })();
  }, [
    assistantMessage,
    beginRevealRequest,
    canInteractWithChallenge,
    coachField,
    commitAssistantTurn,
    conversationHistory,
    isRevealRequestCurrent,
    mapConversationHistoryToChat,
    persistSession,
    requestCoachGuidance,
    resolvedChallengeId,
    revealField,
    selectedMode,
    setAssistantHistory,
    setCoachLoading,
    setAssistantMessage,
    setConversationHistory,
    setRevealLoading,
  ]);

  return {
    handleAssistantSubmit,
  };
}
