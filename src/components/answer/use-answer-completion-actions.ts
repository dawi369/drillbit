import { router } from "expo-router";
import { useCallback } from "react";
import { Alert } from "react-native";

import { summarizeChallengeSession } from "@/lib/ai/prompt-runtime";
import {
  completeChallenge,
  markChallengeInProgress,
  skipChallenge,
} from "@/lib/storage/repository";
import type { ChallengeMode } from "@/lib/widgets/types";

export function useAnswerCompletionActions({
  canInteractWithChallenge,
  resolvedChallengeId,
  selectedMode,
  persistSession,
  refreshResolvedChallenge,
  resetAnswerState,
}: {
  canInteractWithChallenge: boolean;
  resolvedChallengeId: string | null;
  selectedMode: ChallengeMode;
  persistSession: () => Promise<void>;
  refreshResolvedChallenge: () => Promise<unknown>;
  resetAnswerState: (nextMode?: ChallengeMode) => void;
}) {
  const handleSkip = useCallback(() => {
    void (async () => {
      if (!canInteractWithChallenge || !resolvedChallengeId) {
        Alert.alert("no active challenge", "Generate or resume a challenge first.");
        return;
      }

      await skipChallenge(resolvedChallengeId);
      resetAnswerState();
      router.replace("/(tabs)");
    })();
  }, [canInteractWithChallenge, resetAnswerState, resolvedChallengeId]);

  const handleSave = useCallback(() => {
    void (async () => {
      if (!canInteractWithChallenge || !resolvedChallengeId) {
        Alert.alert("no active challenge", "Generate or resume a challenge first.");
        return;
      }

      await persistSession();
      await markChallengeInProgress(resolvedChallengeId, selectedMode);
      await refreshResolvedChallenge();

      Alert.alert(
        "saved",
        "Your notes are saved. This challenge stays active right where you left it.",
      );
    })();
  }, [
    canInteractWithChallenge,
    persistSession,
    refreshResolvedChallenge,
    resolvedChallengeId,
    selectedMode,
  ]);

  const handleDone = useCallback(() => {
    void (async () => {
      if (!canInteractWithChallenge || !resolvedChallengeId) {
        Alert.alert("no active challenge", "Generate or resume a challenge first.");
        return;
      }

      await persistSession();
      await completeChallenge(resolvedChallengeId);
      resetAnswerState();
      router.replace("/(tabs)");

      void (async () => {
        try {
          await summarizeChallengeSession(resolvedChallengeId);
        } catch (error) {
          console.error("background summary failed", error);
        }
      })();
    })();
  }, [canInteractWithChallenge, persistSession, resetAnswerState, resolvedChallengeId]);

  return {
    handleSkip,
    handleSave,
    handleDone,
  };
}
