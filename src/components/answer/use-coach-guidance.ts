import { useCallback, useEffect, useRef, useState } from "react";

import {
  AUTO_COACH_IDLE_MS,
  getAutoCoachTriggerReason,
} from "@/components/answer/answer-flow";
import { streamCoachGuidance } from "@/lib/ai/prompt-runtime";
import { debugLog } from "@/lib/debug";
import type {
  ChallengeConversationTurn,
  CoachTriggerReason,
} from "@/lib/storage/types";

type CommitAssistantTurn = (args: {
  currentHistory: ChallengeConversationTurn[];
  mode: "coach" | "reveal";
  userText?: string;
  assistantText: string;
  assistantAnswer?: string;
}) => ChallengeConversationTurn[];

export function useCoachGuidance({
  selectedMode,
  resolvedChallengeId,
  hasChallenge,
  normalizedNotesDraft,
  conversationHistory,
  isCoachLoading,
  coachField,
  setCoachLoading,
  setConversationHistory,
  commitAssistantTurn,
  persistSession,
}: {
  selectedMode: "solo" | "coach" | "reveal";
  resolvedChallengeId: string | null;
  hasChallenge: boolean;
  normalizedNotesDraft: string;
  conversationHistory: ChallengeConversationTurn[];
  isCoachLoading: boolean;
  coachField: {
    begin: () => void;
    streamText: (value: string) => void;
    finish: (value: string, nextAnswer?: string | null) => void;
    fail: (message: string) => void;
  };
  setCoachLoading: (value: boolean) => void;
  setConversationHistory: React.Dispatch<React.SetStateAction<ChallengeConversationTurn[]>>;
  commitAssistantTurn: CommitAssistantTurn;
  persistSession: (overrides?: {
    assistantDraft?: string;
    conversationHistory?: ChallengeConversationTurn[];
  }) => Promise<void>;
}) {
  const [lastAutoCoachAt, setLastAutoCoachAt] = useState<number | null>(null);
  const [lastAutoCoachNotesSnapshot, setLastAutoCoachNotesSnapshot] = useState("");
  const requestIdRef = useRef(0);

  const invalidateCoachRequest = useCallback(() => {
    requestIdRef.current += 1;
  }, []);

  const requestCoachGuidance = useCallback(
    async ({
      trigger,
      latestUserRequest,
      appendToHistory = false,
      onPartialGuidance,
    }: {
      trigger: CoachTriggerReason;
      latestUserRequest?: string;
      appendToHistory?: boolean;
      onPartialGuidance?: (partialText: string) => void;
    }) => {
      if (!resolvedChallengeId) {
        return null;
      }

      debugLog("coach", "requesting guidance", {
        challengeId: resolvedChallengeId,
        trigger,
        appendToHistory,
        hasLatestUserRequest: Boolean(latestUserRequest),
      });

      const requestId = ++requestIdRef.current;
      coachField.begin();
      let streamedText = "";

      let result;

      try {
        result = await streamCoachGuidance(resolvedChallengeId, {
          coachTrigger: trigger,
          latestUserRequest,
          onTextDelta: (textDelta) => {
            if (requestId !== requestIdRef.current) {
              return;
            }

            streamedText += textDelta;
            coachField.streamText(streamedText);
            onPartialGuidance?.(streamedText);
          },
        });
      } catch (error) {
        if (requestId !== requestIdRef.current) {
          debugLog("coach", "ignored stale coach error", {
            challengeId: resolvedChallengeId,
            trigger,
          });
          return null;
        }

        throw error;
      }

      if (requestId !== requestIdRef.current) {
        debugLog("coach", "discarded stale guidance result", {
          challengeId: resolvedChallengeId,
          trigger,
        });
        return null;
      }

      coachField.finish(result.output.guidance);

      if (appendToHistory) {
        setConversationHistory((current) => {
          const lastAssistantTurn = [...current]
            .reverse()
            .find((turn) => turn.role === "assistant" && turn.mode === "coach");

          if (lastAssistantTurn?.text === result.output.guidance) {
            return current;
          }

          const nextHistory = commitAssistantTurn({
            currentHistory: current,
            mode: "coach",
            assistantText: result.output.guidance,
          });

          void persistSession({ conversationHistory: nextHistory });
          return nextHistory;
        });
      }

      return result;
    },
    [
      coachField,
      commitAssistantTurn,
      persistSession,
      resolvedChallengeId,
      setConversationHistory,
    ],
  );

  useEffect(() => {
    if (selectedMode !== "coach") {
      return;
    }

    if (!resolvedChallengeId || !hasChallenge || isCoachLoading) {
      return;
    }

    const trigger = getAutoCoachTriggerReason({
      selectedMode,
      resolvedChallengeId,
      hasChallenge,
      isCoachLoading,
      normalizedNotesDraft,
      conversationHistory,
      lastAutoCoachAt,
      lastAutoCoachNotesSnapshot,
    });

    if (!trigger) {
      return;
    }

    const timeout = setTimeout(() => {
      void (async () => {
        setCoachLoading(true);

        try {
          const result = await requestCoachGuidance({
            trigger,
            appendToHistory: true,
          });

          if (!result) {
            return;
          }

          setLastAutoCoachAt(Date.now());
          setLastAutoCoachNotesSnapshot(normalizedNotesDraft);
          debugLog("coach", "loaded auto guidance", {
            challengeId: resolvedChallengeId,
            trigger,
          });
        } catch (error) {
          debugLog("coach", "auto guidance failed", {
            challengeId: resolvedChallengeId,
            error: error instanceof Error ? error.message : String(error),
          });
          coachField.fail(
            error instanceof Error ? error.message : "assistant request failed",
          );
        } finally {
          setCoachLoading(false);
        }
      })();
    }, AUTO_COACH_IDLE_MS);

    return () => clearTimeout(timeout);
  }, [
    coachField,
    conversationHistory,
    hasChallenge,
    isCoachLoading,
    lastAutoCoachAt,
    lastAutoCoachNotesSnapshot.length,
    normalizedNotesDraft,
    requestCoachGuidance,
    resolvedChallengeId,
    selectedMode,
    setCoachLoading,
  ]);

  return {
    invalidateCoachRequest,
    requestCoachGuidance,
  };
}
