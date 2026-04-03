import { useCallback, useEffect, useState } from "react";

import { resolveAnswerMode } from "@/components/answer/answer-flow";
import { debugLog } from "@/lib/debug";
import { subscribeToModelsRefresh } from "@/lib/models-refresh";
import { subscribeToSettingsRefresh } from "@/lib/settings-refresh";
import {
  ensureDefaultModels,
  ensureDefaultSettings,
  getChallengeById,
  getChallengeSession,
  listModels,
  refreshReadyChallengeExpirations,
} from "@/lib/storage/repository";
import type {
  ChallengeConversationTurn,
  ChallengeRecord,
  ModelRecord,
} from "@/lib/storage/types";
import type { ChallengeMode } from "@/lib/widgets/types";

function isActiveAnswerChallenge(record: ChallengeRecord | null | undefined) {
  return record?.lifecycle === "ready" || record?.lifecycle === "in_progress";
}

export function useAnswerScreenState({
  resolvedChallengeId,
  routeMode,
  resetAnswerState,
  resetCoachField,
  resetRevealField,
  syncPersistedDraftSnapshot,
  setSelectedMode,
  setNotesDraft,
  setAssistantDraft,
  setAssistantMessage,
  setConversationHistory,
}: {
  resolvedChallengeId: string | null;
  routeMode: ChallengeMode | null;
  resetAnswerState: (nextMode?: ChallengeMode) => void;
  resetCoachField: (nextStatus?: "idle" | "thinking" | "streaming" | "done" | "error") => void;
  resetRevealField: (nextStatus?: "idle" | "thinking" | "streaming" | "done" | "error") => void;
  syncPersistedDraftSnapshot: (snapshot?: {
    selectedMode?: ChallengeMode;
    notesDraft?: string;
    assistantDraft?: string;
    conversationHistory?: ChallengeConversationTurn[];
  }) => void;
  setSelectedMode: React.Dispatch<React.SetStateAction<ChallengeMode>>;
  setNotesDraft: React.Dispatch<React.SetStateAction<string>>;
  setAssistantDraft: React.Dispatch<React.SetStateAction<string>>;
  setAssistantMessage: React.Dispatch<React.SetStateAction<string>>;
  setConversationHistory: React.Dispatch<React.SetStateAction<ChallengeConversationTurn[]>>;
}) {
  const [availableModels, setAvailableModels] = useState<ModelRecord[]>([]);
  const [selectedModelId, setSelectedModelId] = useState<string | undefined>();
  const [challenge, setChallenge] = useState<ChallengeRecord | null>(null);
  const [isChallengeLoading, setChallengeLoading] = useState(true);

  const loadModelState = useCallback(async () => {
    await ensureDefaultModels();
    const [models, settings] = await Promise.all([
      listModels({ includeDisabled: false }),
      ensureDefaultSettings(),
    ]);

    setAvailableModels(models);
    setSelectedModelId(settings.selectedModelId ?? models[0]?.id);
  }, []);

  const refreshResolvedChallenge = useCallback(async () => {
    if (!resolvedChallengeId) {
      resetAnswerState();
      return null;
    }

    const latestChallenge = await getChallengeById(resolvedChallengeId);
    if (!isActiveAnswerChallenge(latestChallenge)) {
      resetAnswerState();
      return null;
    }

    setChallenge(latestChallenge);
    return latestChallenge;
  }, [resetAnswerState, resolvedChallengeId]);

  useEffect(() => {
    let isMounted = true;

    async function loadScreenState() {
      setChallengeLoading(true);
      debugLog("answer", "loading screen state", {
        resolvedChallengeId,
      });

      const [, models, settings, existingChallenge, existingSession] =
        await Promise.all([
          ensureDefaultModels(),
          listModels({ includeDisabled: false }),
          ensureDefaultSettings(),
          resolvedChallengeId
            ? getChallengeById(resolvedChallengeId)
            : Promise.resolve(null),
          resolvedChallengeId
            ? getChallengeSession(resolvedChallengeId)
            : Promise.resolve(null),
        ]);
      await refreshReadyChallengeExpirations(settings);

      if (!isMounted) {
        return;
      }

      debugLog("answer", "loaded screen state", {
        resolvedChallengeId,
        foundChallenge: Boolean(existingChallenge),
        foundSession: Boolean(existingSession),
        selectedModelId: settings.selectedModelId,
      });

      setAvailableModels(models);
      setSelectedModelId(settings.selectedModelId ?? models[0]?.id);

      if (!isActiveAnswerChallenge(existingChallenge)) {
        resetAnswerState();
        setChallengeLoading(false);
        return;
      }

      setChallenge(existingChallenge);

      if (existingSession) {
        setSelectedMode(
          resolveAnswerMode({
            routeMode,
            sessionMode: existingSession.selectedMode,
            preferredMode: settings.preferredMode,
          }),
        );
        setNotesDraft(existingSession.notesDraft ?? "");
        setAssistantDraft(existingSession.assistantDraft ?? "");
        setAssistantMessage(existingSession.assistantDraft ?? "");
        setConversationHistory(existingSession.conversationHistory);
        syncPersistedDraftSnapshot({
          selectedMode: resolveAnswerMode({
            routeMode,
            sessionMode: existingSession.selectedMode,
            preferredMode: settings.preferredMode,
          }),
          notesDraft: existingSession.notesDraft,
          assistantDraft: existingSession.assistantDraft,
          conversationHistory: existingSession.conversationHistory,
        });
      } else {
        setSelectedMode(
          resolveAnswerMode({
            routeMode,
            preferredMode: settings.preferredMode,
          }),
        );
        setNotesDraft("");
        setAssistantDraft("");
        setAssistantMessage("");
        setConversationHistory([]);
        syncPersistedDraftSnapshot({
          selectedMode: resolveAnswerMode({
            routeMode,
            preferredMode: settings.preferredMode,
          }),
          conversationHistory: [],
        });
        resetCoachField();
        resetRevealField();
      }

      setChallengeLoading(false);
    }

    void loadScreenState();

    return () => {
      isMounted = false;
    };
  }, [
    resolvedChallengeId,
    resetCoachField,
    resetAnswerState,
    resetRevealField,
    routeMode,
    setAssistantDraft,
    setAssistantMessage,
    setConversationHistory,
    setNotesDraft,
    setSelectedMode,
    syncPersistedDraftSnapshot,
  ]);

  useEffect(() => {
    return subscribeToModelsRefresh(() => {
      void loadModelState();
    });
  }, [loadModelState]);

  useEffect(() => {
    return subscribeToSettingsRefresh(() => {
      void loadModelState();
    });
  }, [loadModelState]);

  return {
    availableModels,
    challenge,
    isChallengeLoading,
    refreshResolvedChallenge,
    selectedModelId,
    setChallenge,
    setSelectedModelId,
  };
}
