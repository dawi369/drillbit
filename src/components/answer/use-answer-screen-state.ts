import { useCallback, useEffect, useState } from "react";

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
  coachField,
  revealField,
  syncPersistedDraftSnapshot,
  setSelectedMode,
  setNotesDraft,
  setAssistantDraft,
  setAssistantMessage,
  setUpdatedAt,
  setConversationHistory,
}: {
  resolvedChallengeId: string | null;
  routeMode: ChallengeMode | null;
  resetAnswerState: (nextMode?: ChallengeMode) => void;
  coachField: {
    reset: (nextStatus?: "idle" | "thinking" | "streaming" | "done" | "error") => void;
  };
  revealField: {
    reset: (nextStatus?: "idle" | "thinking" | "streaming" | "done" | "error") => void;
  };
  syncPersistedDraftSnapshot: (snapshot?: {
    notesDraft?: string;
    assistantDraft?: string;
  }) => void;
  setSelectedMode: React.Dispatch<React.SetStateAction<ChallengeMode>>;
  setNotesDraft: React.Dispatch<React.SetStateAction<string>>;
  setAssistantDraft: React.Dispatch<React.SetStateAction<string>>;
  setAssistantMessage: React.Dispatch<React.SetStateAction<string>>;
  setUpdatedAt: React.Dispatch<React.SetStateAction<string>>;
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
          existingSession.selectedMode ?? settings.preferredMode ?? routeMode ?? "coach",
        );
        setNotesDraft(existingSession.notesDraft ?? "");
        setAssistantDraft(existingSession.assistantDraft ?? "");
        setAssistantMessage(existingSession.assistantDraft ?? "");
        setUpdatedAt(existingSession.updatedAt);
        setConversationHistory(existingSession.conversationHistory);
        syncPersistedDraftSnapshot({
          notesDraft: existingSession.notesDraft,
          assistantDraft: existingSession.assistantDraft,
        });
      } else {
        setSelectedMode(settings.preferredMode ?? routeMode ?? "coach");
        setNotesDraft("");
        setAssistantDraft("");
        setAssistantMessage("");
        setUpdatedAt(new Date().toISOString());
        setConversationHistory([]);
        syncPersistedDraftSnapshot();
        coachField.reset();
        revealField.reset();
      }

      setChallengeLoading(false);
    }

    void loadScreenState();

    return () => {
      isMounted = false;
    };
  }, [
    coachField,
    resolvedChallengeId,
    resetAnswerState,
    revealField,
    routeMode,
    setAssistantDraft,
    setAssistantMessage,
    setConversationHistory,
    setNotesDraft,
    setSelectedMode,
    setUpdatedAt,
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
