import { router } from "expo-router";
import { useCallback } from "react";
import { Alert } from "react-native";

import { summarizeChallengeSession } from "@/lib/ai/prompt-runtime";
import { debugLog } from "@/lib/debug";
import {
  completeChallenge,
  markChallengeInProgress,
  skipChallenge,
} from "@/lib/storage/repository";
import type { ChallengeMode } from "@/lib/widgets/types";

export function useAnswerCompletionActions({
  canInteractWithChallenge,
  resolvedChallengeId,
  persistSession,
  refreshResolvedChallenge,
  resetAnswerDraftState,
}: {
  canInteractWithChallenge: boolean;
  resolvedChallengeId: string | null;
  persistSession: () => Promise<void>;
  refreshResolvedChallenge: () => Promise<unknown>;
  resetAnswerDraftState: (nextMode?: ChallengeMode) => void;
}) {
  const handleSkip = useCallback(() => {
    void (async () => {
      if (!canInteractWithChallenge || !resolvedChallengeId) {
        Alert.alert("No active challenge", "Generate or resume a challenge first.");
        return;
      }

      await skipChallenge(resolvedChallengeId);
      resetAnswerDraftState();
      router.replace("/(tabs)");
    })();
  }, [canInteractWithChallenge, resetAnswerDraftState, resolvedChallengeId]);

  const handleSave = useCallback(() => {
    void (async () => {
      if (!canInteractWithChallenge || !resolvedChallengeId) {
        Alert.alert("No active challenge", "Generate or resume a challenge first.");
        return;
      }

      await persistSession();
      await markChallengeInProgress(resolvedChallengeId);
      await refreshResolvedChallenge();

      Alert.alert(
        "Saved",
        "Your notes are saved. This challenge stays active right where you left it.",
      );
    })();
  }, [
    canInteractWithChallenge,
    persistSession,
    refreshResolvedChallenge,
    resolvedChallengeId,
  ]);

  const handleDone = useCallback(() => {
    void (async () => {
      if (!canInteractWithChallenge || !resolvedChallengeId) {
        Alert.alert("No active challenge", "Generate or resume a challenge first.");
        return;
      }

      await persistSession();
      await completeChallenge(resolvedChallengeId);
      resetAnswerDraftState();
      router.replace("/(tabs)");

      void (async () => {
        try {
          await summarizeChallengeSession(resolvedChallengeId);
        } catch (error) {
          debugLog("answer", "background summary failed", error);
        }
      })();
    })();
  }, [canInteractWithChallenge, persistSession, resetAnswerDraftState, resolvedChallengeId]);

  return {
    handleSkip,
    handleSave,
    handleDone,
  };
}
