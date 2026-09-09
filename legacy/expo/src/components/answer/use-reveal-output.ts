import { useEffect } from "react";

import { streamRevealAnswer } from "@/lib/ai/prompt-runtime";
import { debugLog } from "@/lib/debug";
import type { ChallengeConversationTurn } from "@/lib/storage/types";

type CommitAssistantTurn = (args: {
  currentHistory: ChallengeConversationTurn[];
  mode: "coach" | "reveal";
  userText?: string;
  assistantText: string;
  assistantAnswer?: string;
}) => ChallengeConversationTurn[];

export function useRevealOutput({
  selectedMode,
  resolvedChallengeId,
  hasChallenge,
  conversationHistory,
  revealField,
  isRevealLoading,
  setRevealLoading,
  setConversationHistory,
  commitAssistantTurn,
  persistSession,
  beginRevealRequest,
  isRevealRequestCurrent,
}: {
  selectedMode: "solo" | "coach" | "reveal";
  resolvedChallengeId: string | null;
  hasChallenge: boolean;
  conversationHistory: ChallengeConversationTurn[];
  revealField: {
    reset: (nextStatus?: "idle" | "thinking" | "streaming" | "done" | "error") => void;
    begin: () => void;
    streamRevealDraft: (rawText: string) => void;
    finish: (value: string, nextAnswer?: string | null) => void;
    fail: (message: string) => void;
  };
  isRevealLoading: boolean;
  setRevealLoading: (value: boolean) => void;
  setConversationHistory: React.Dispatch<React.SetStateAction<ChallengeConversationTurn[]>>;
  commitAssistantTurn: CommitAssistantTurn;
  persistSession: (overrides?: {
    assistantDraft?: string;
    conversationHistory?: ChallengeConversationTurn[];
  }) => Promise<void>;
  beginRevealRequest: () => number;
  isRevealRequestCurrent: (requestId: number) => boolean;
}) {
  useEffect(() => {
    if (selectedMode === "solo") {
      revealField.reset();
      return;
    }

    if (selectedMode === "coach") {
      revealField.reset();
      return;
    }

    if (!resolvedChallengeId || !hasChallenge) {
      return;
    }

    if (isRevealLoading) {
      return;
    }

    const challengeId = resolvedChallengeId;

    let isMounted = true;

    async function loadRevealOutput() {
      if (selectedMode !== "reveal") {
        return;
      }

      const latestRevealTurn = [...conversationHistory]
        .reverse()
        .find((turn) => turn.role === "assistant" && turn.mode === "reveal");

      if (latestRevealTurn?.answer) {
        debugLog("reveal", "reusing persisted reveal answer", {
          challengeId,
        });
        revealField.finish(latestRevealTurn.text, latestRevealTurn.answer);
        return;
      }

      const requestId = beginRevealRequest();
      setRevealLoading(true);
      debugLog("answer", "loading assistant output", {
        resolvedChallengeId,
        selectedMode,
      });

      try {
        revealField.begin();
        let streamedText = "";

        let result;

        try {
          result = await streamRevealAnswer(challengeId, {
            onTextDelta: (textDelta) => {
              if (!isRevealRequestCurrent(requestId)) {
                return;
              }

              streamedText += textDelta;
              revealField.streamRevealDraft(streamedText);
            },
          });
        } catch (error) {
          if (!isRevealRequestCurrent(requestId)) {
            debugLog("reveal", "ignored stale reveal error", {
              challengeId,
            });
            return;
          }

          throw error;
        }

        if (!isMounted || !isRevealRequestCurrent(requestId)) {
          debugLog("reveal", "discarded stale reveal result", {
            challengeId,
          });
          return;
        }

        revealField.finish(result.output.guidance, result.output.answer);
        setConversationHistory((current) => {
          const lastRevealTurn = [...current]
            .reverse()
            .find((turn) => turn.role === "assistant" && turn.mode === "reveal");

          if (
            lastRevealTurn?.text === result.output.guidance &&
            lastRevealTurn.answer === result.output.answer
          ) {
            return current;
          }

          const nextHistory = commitAssistantTurn({
            currentHistory: current,
            mode: "reveal",
            assistantText: result.output.guidance,
            assistantAnswer: result.output.answer,
          });

          void persistSession({ conversationHistory: nextHistory });
          return nextHistory;
        });

        debugLog("answer", "loaded reveal answer", {
          resolvedChallengeId,
        });
      } catch (error) {
        debugLog("answer", "assistant output failed", {
          resolvedChallengeId,
          selectedMode,
          error: error instanceof Error ? error.message : String(error),
        });

        if (!isMounted || !isRevealRequestCurrent(requestId)) {
          return;
        }

        revealField.fail(
          error instanceof Error ? error.message : "assistant request failed",
        );
      } finally {
        if (isMounted && isRevealRequestCurrent(requestId)) {
          setRevealLoading(false);
        }
      }
    }

    void loadRevealOutput();

    return () => {
      isMounted = false;
    };
  }, [
    commitAssistantTurn,
    conversationHistory,
    beginRevealRequest,
    hasChallenge,
    isRevealLoading,
    isRevealRequestCurrent,
    persistSession,
    resolvedChallengeId,
    revealField,
    selectedMode,
    setRevealLoading,
    setConversationHistory,
  ]);
}
