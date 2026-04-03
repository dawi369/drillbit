import { useCallback, useEffect, useMemo, useState } from "react";

import {
  getLatestAssistantMessage,
  mapConversationHistoryToChat,
  type AssistantChatMessage,
} from "@/components/answer/assistant-history";
import {
  getAssistantThreadMode,
  normalizeCoachText,
} from "@/components/answer/answer-flow";
import { useAnswerActions } from "@/components/answer/use-answer-actions";
import { useAnswerCompletionActions } from "@/components/answer/use-answer-completion-actions";
import { useAnswerScreenState } from "@/components/answer/use-answer-screen-state";
import { useAssistantFieldState } from "@/components/answer/use-assistant-field-state";
import { useChallengeSessionPersistence } from "@/components/answer/use-challenge-session-persistence";
import { useCoachGuidance } from "@/components/answer/use-coach-guidance";
import { useRequestSequence } from "@/components/answer/use-request-sequence";
import { useRevealOutput } from "@/components/answer/use-reveal-output";
import { debugLog } from "@/lib/debug";
import { markChallengeInProgress, selectModel } from "@/lib/storage/repository";
import type { ChallengeConversationTurn } from "@/lib/storage/types";
import type { ChallengeMode } from "@/lib/widgets/types";

type CommitAssistantTurn = (args: {
  currentHistory: ChallengeConversationTurn[];
  mode: "coach" | "reveal";
  userText?: string;
  assistantText: string;
  assistantAnswer?: string;
}) => ChallengeConversationTurn[];

function commitAssistantTurn({
  currentHistory,
  mode,
  userText,
  assistantText,
  assistantAnswer,
}: {
  currentHistory: ChallengeConversationTurn[];
  mode: Extract<ChallengeMode, "coach" | "reveal">;
  userText?: string;
  assistantText: string;
  assistantAnswer?: string;
}): ChallengeConversationTurn[] {
  const assistantTurnId = `assistant-${Date.now()}`;
  const nextHistory = [...currentHistory];

  if (userText) {
    nextHistory.push({
      id: `user-${assistantTurnId}`,
      role: "user",
      mode,
      text: userText,
      createdAt: new Date().toISOString(),
    });
  }

  nextHistory.push({
    id: assistantTurnId,
    role: "assistant",
    mode,
    text: assistantText,
    answer: assistantAnswer,
    createdAt: new Date().toISOString(),
  });

  return nextHistory;
}

export function useAnswerController({
  resolvedChallengeId,
  routeMode,
}: {
  resolvedChallengeId: string | null;
  routeMode: ChallengeMode | null;
}) {
  const [selectedMode, setSelectedMode] = useState<ChallengeMode>(routeMode ?? "solo");
  const [notesDraft, setNotesDraft] = useState("");
  const [assistantDraft, setAssistantDraft] = useState("");
  const [assistantMessage, setAssistantMessage] = useState("");
  const [assistantHistory, setAssistantHistory] = useState<AssistantChatMessage[]>([]);
  const [conversationHistory, setConversationHistory] = useState<
    ChallengeConversationTurn[]
  >([]);
  const [isCoachLoading, setCoachLoading] = useState(false);
  const [isRevealLoading, setRevealLoading] = useState(false);
  const coachField = useAssistantFieldState();
  const revealField = useAssistantFieldState();
  const revealRequest = useRequestSequence();

  const resetAnswerState = useCallback(
    (nextMode: ChallengeMode = routeMode ?? "solo") => {
      setChallenge(null);
      setSelectedMode(nextMode);
      setNotesDraft("");
      setAssistantDraft("");
      setConversationHistory([]);
      setAssistantHistory([]);
      coachField.reset(nextMode === "coach" ? "idle" : "done");
      revealField.reset(nextMode === "reveal" ? "idle" : "done");
      setAssistantMessage("");
    },
    [coachField, revealField, routeMode],
  );

  const normalizedNotesDraft = useMemo(
    () => normalizeCoachText(notesDraft),
    [notesDraft],
  );
  const assistantThreadMode = getAssistantThreadMode(selectedMode);
  const isAssistantLoading =
    selectedMode === "coach"
      ? isCoachLoading
      : selectedMode === "reveal"
        ? isRevealLoading
        : false;

  const { persistSession, syncPersistedDraftSnapshot } = useChallengeSessionPersistence({
    resolvedChallengeId,
    selectedMode,
    notesDraft,
    assistantDraft,
    conversationHistory,
  });

  const {
    availableModels,
    challenge,
    isChallengeLoading,
    refreshResolvedChallenge,
    selectedModelId,
    setChallenge,
    setSelectedModelId,
  } = useAnswerScreenState({
    resolvedChallengeId,
    routeMode,
    resetAnswerState,
    resetCoachField: coachField.reset,
    resetRevealField: revealField.reset,
    syncPersistedDraftSnapshot,
    setSelectedMode,
    setNotesDraft,
    setAssistantDraft,
    setAssistantMessage,
    setConversationHistory,
  });

  const canInteractWithChallenge = Boolean(
    resolvedChallengeId && challenge && !isChallengeLoading,
  );

  const { invalidateCoachRequest, requestCoachGuidance } = useCoachGuidance({
    selectedMode,
    resolvedChallengeId,
    hasChallenge: Boolean(challenge),
    normalizedNotesDraft,
    conversationHistory,
    isCoachLoading,
    coachField,
    setCoachLoading,
    setConversationHistory,
    commitAssistantTurn,
    persistSession,
  });

  useEffect(() => {
    if (selectedMode !== "coach") {
      invalidateCoachRequest();
      setCoachLoading(false);
    }

    if (selectedMode !== "reveal") {
      revealRequest.invalidateRequest();
      setRevealLoading(false);
    }
  }, [invalidateCoachRequest, revealRequest, selectedMode]);

  useEffect(() => {
    invalidateCoachRequest();
    revealRequest.invalidateRequest();
    setCoachLoading(false);
    setRevealLoading(false);
  }, [invalidateCoachRequest, revealRequest, resolvedChallengeId]);

  useEffect(() => {
    if (selectedMode === "solo") {
      setAssistantHistory([]);
      return;
    }

    setAssistantHistory(
      mapConversationHistoryToChat(conversationHistory, assistantThreadMode),
    );
  }, [assistantThreadMode, conversationHistory, selectedMode]);

  useEffect(() => {
    if (!resolvedChallengeId || !challenge) {
      return;
    }

    if (challenge.lifecycle !== "in_progress") {
      debugLog("answer", "marking challenge in progress", {
        resolvedChallengeId,
        selectedMode,
      });

      void markChallengeInProgress(resolvedChallengeId, selectedMode);
    }

    void persistSession({ selectedMode }, { broadcast: false });
  }, [challenge, persistSession, resolvedChallengeId, selectedMode]);

  useRevealOutput({
    selectedMode,
    resolvedChallengeId,
    hasChallenge: Boolean(challenge),
    conversationHistory,
    revealField,
    isRevealLoading,
    setRevealLoading,
    setConversationHistory,
    commitAssistantTurn,
    persistSession,
    beginRevealRequest: revealRequest.beginRequest,
    isRevealRequestCurrent: revealRequest.isCurrentRequest,
  });

  const { handleSkip, handleSave, handleDone } = useAnswerCompletionActions({
    canInteractWithChallenge,
    resolvedChallengeId,
    selectedMode,
    persistSession: () => persistSession(),
    refreshResolvedChallenge,
    resetAnswerState,
  });

  const { handleAssistantSubmit } = useAnswerActions({
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
    mapConversationHistoryToChat: (history) =>
      mapConversationHistoryToChat(history, assistantThreadMode),
    commitAssistantTurn,
    coachField,
    revealField,
    beginRevealRequest: revealRequest.beginRequest,
    isRevealRequestCurrent: revealRequest.isCurrentRequest,
  });

  const latestAssistantMessage = useMemo(
    () => getLatestAssistantMessage(assistantHistory, assistantThreadMode),
    [assistantHistory, assistantThreadMode],
  );

  const assistantGuidance =
    selectedMode === "coach"
      ? coachField.text
      : selectedMode === "reveal"
        ? revealField.text
        : null;
  const assistantStatus =
    selectedMode === "coach"
      ? coachField.status
      : selectedMode === "reveal"
        ? revealField.status
        : undefined;

  const handleSelectModel = useCallback((modelId: string) => {
    setSelectedModelId(modelId);
    void selectModel(modelId);
  }, [setSelectedModelId]);

  return {
    assistantDraft,
    assistantGuidance,
    assistantHistory,
    assistantMessage,
    assistantStatus,
    availableModels,
    canInteractWithChallenge,
    challenge,
    handleAssistantSubmit,
    handleDone,
    handleSave,
    handleSelectModel,
    handleSkip,
    isAssistantLoading,
    isChallengeLoading,
    latestAssistantMessage,
    notesDraft,
    revealAnswer: revealField.answer,
    selectedMode,
    selectedModelId,
    setAssistantDraft,
    setAssistantMessage,
    setSelectedMode,
    setNotesDraft,
  };
}
