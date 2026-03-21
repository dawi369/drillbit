import { useCallback, useEffect, useRef } from "react";

import { debugLog } from "@/lib/debug";
import { upsertChallengeSession } from "@/lib/storage/repository";
import type {
  ChallengeConversationTurn,
  ChallengeSessionRecord,
} from "@/lib/storage/types";
import type { ChallengeMode } from "@/lib/widgets/types";

type PersistSessionOptions = {
  broadcast?: boolean;
};

type DraftSnapshot = {
  challengeId: string | null;
  notesDraft: string;
  assistantDraft: string;
};

export function useChallengeSessionPersistence({
  resolvedChallengeId,
  selectedMode,
  notesDraft,
  assistantDraft,
  conversationHistory,
}: {
  resolvedChallengeId: string | null;
  selectedMode: ChallengeMode;
  notesDraft: string;
  assistantDraft: string;
  conversationHistory: ChallengeConversationTurn[];
}) {
  const lastPersistedDraftsRef = useRef<DraftSnapshot>({
    challengeId: resolvedChallengeId,
    notesDraft: "",
    assistantDraft: "",
  });

  const syncPersistedDraftSnapshot = useCallback(
    (snapshot?: { notesDraft?: string; assistantDraft?: string }) => {
      lastPersistedDraftsRef.current = {
        challengeId: resolvedChallengeId,
        notesDraft: snapshot?.notesDraft ?? "",
        assistantDraft: snapshot?.assistantDraft ?? "",
      };
    },
    [resolvedChallengeId],
  );

  const persistSession = useCallback(
    async (
      overrides: Partial<ChallengeSessionRecord> = {},
      options?: PersistSessionOptions,
    ) => {
      const nextUpdatedAt = overrides.updatedAt ?? new Date().toISOString();
      const nextNotesDraft = overrides.notesDraft ?? notesDraft;
      const nextAssistantDraft = overrides.assistantDraft ?? assistantDraft;

      debugLog("session", "persisting challenge session", {
        challengeId: resolvedChallengeId,
        broadcast: options?.broadcast ?? true,
        hasConversationHistoryOverride: Boolean(overrides.conversationHistory),
        selectedMode: overrides.selectedMode ?? selectedMode,
      });

      await upsertChallengeSession(
        {
          challengeId: resolvedChallengeId ?? "",
          selectedMode: overrides.selectedMode ?? selectedMode,
          notesDraft: nextNotesDraft,
          assistantDraft: nextAssistantDraft,
          conversationHistory: overrides.conversationHistory ?? conversationHistory,
          updatedAt: nextUpdatedAt,
        },
        options,
      );

      lastPersistedDraftsRef.current = {
        challengeId: resolvedChallengeId,
        notesDraft: nextNotesDraft,
        assistantDraft: nextAssistantDraft,
      };
    },
    [assistantDraft, conversationHistory, notesDraft, resolvedChallengeId, selectedMode],
  );

  useEffect(() => {
    if (!resolvedChallengeId) {
      return;
    }

    const lastPersistedDrafts = lastPersistedDraftsRef.current;
    const draftsChanged =
      lastPersistedDrafts.challengeId !== resolvedChallengeId ||
      lastPersistedDrafts.notesDraft !== notesDraft ||
      lastPersistedDrafts.assistantDraft !== assistantDraft;

    if (!draftsChanged) {
      return;
    }

    const timeout = setTimeout(() => {
      debugLog("session", "persisting draft snapshot", {
        challengeId: resolvedChallengeId,
        notesLength: notesDraft.length,
        assistantLength: assistantDraft.length,
      });
      void persistSession(
        {
          notesDraft,
          assistantDraft,
        },
        { broadcast: false },
      );
    }, 400);

    return () => clearTimeout(timeout);
  }, [assistantDraft, notesDraft, persistSession, resolvedChallengeId]);

  return {
    persistSession,
    syncPersistedDraftSnapshot,
  };
}
