import { useCallback, useEffect, useRef } from "react";

import { hasSessionSnapshotChanges } from "@/components/answer/answer-flow";
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
  selectedMode: ChallengeMode;
  notesDraft: string;
  assistantDraft: string;
  conversationHistory: ChallengeConversationTurn[];
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
    selectedMode,
    notesDraft: "",
    assistantDraft: "",
    conversationHistory: [],
  });
  const latestSnapshotRef = useRef<DraftSnapshot>({
    challengeId: resolvedChallengeId,
    selectedMode,
    notesDraft,
    assistantDraft,
    conversationHistory,
  });
  const persistTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const persistSnapshot = useCallback(
    async (
      snapshot: DraftSnapshot,
      overrides: Partial<ChallengeSessionRecord> = {},
      options?: PersistSessionOptions,
    ) => {
      if (!snapshot.challengeId) {
        return;
      }

      const nextUpdatedAt = overrides.updatedAt ?? new Date().toISOString();
      const nextNotesDraft = overrides.notesDraft ?? snapshot.notesDraft;
      const nextAssistantDraft = overrides.assistantDraft ?? snapshot.assistantDraft;
      const nextConversationHistory =
        overrides.conversationHistory ?? snapshot.conversationHistory;

      debugLog("session", "persisting challenge session", {
        challengeId: snapshot.challengeId,
        broadcast: options?.broadcast ?? true,
        hasConversationHistoryOverride: Boolean(overrides.conversationHistory),
        selectedMode: overrides.selectedMode ?? snapshot.selectedMode,
      });

      await upsertChallengeSession(
        {
          challengeId: snapshot.challengeId,
          selectedMode: overrides.selectedMode ?? snapshot.selectedMode,
          notesDraft: nextNotesDraft,
          assistantDraft: nextAssistantDraft,
          conversationHistory: nextConversationHistory,
          updatedAt: nextUpdatedAt,
        },
        options,
      );

      lastPersistedDraftsRef.current = {
        challengeId: snapshot.challengeId,
        selectedMode: overrides.selectedMode ?? snapshot.selectedMode,
        notesDraft: nextNotesDraft,
        assistantDraft: nextAssistantDraft,
        conversationHistory: nextConversationHistory,
      };
    },
    [],
  );

  const syncPersistedDraftSnapshot = useCallback(
    (snapshot?: {
      selectedMode?: ChallengeMode;
      notesDraft?: string;
      assistantDraft?: string;
      conversationHistory?: ChallengeConversationTurn[];
    }) => {
      lastPersistedDraftsRef.current = {
        challengeId: resolvedChallengeId,
        selectedMode:
          snapshot?.selectedMode ?? latestSnapshotRef.current.selectedMode,
        notesDraft: snapshot?.notesDraft ?? "",
        assistantDraft: snapshot?.assistantDraft ?? "",
        conversationHistory:
          snapshot?.conversationHistory ?? latestSnapshotRef.current.conversationHistory,
      };
    },
    [resolvedChallengeId],
  );

  const persistSession = useCallback(
    async (
      overrides: Partial<ChallengeSessionRecord> = {},
      options?: PersistSessionOptions,
    ) => {
      await persistSnapshot(
        {
          challengeId: resolvedChallengeId,
          selectedMode,
          notesDraft,
          assistantDraft,
          conversationHistory,
        },
        overrides,
        options,
      );
    },
    [
      assistantDraft,
      conversationHistory,
      notesDraft,
      persistSnapshot,
      resolvedChallengeId,
      selectedMode,
    ],
  );

  useEffect(() => {
    latestSnapshotRef.current = {
      challengeId: resolvedChallengeId,
      selectedMode,
      notesDraft,
      assistantDraft,
      conversationHistory,
    };
  }, [assistantDraft, conversationHistory, notesDraft, resolvedChallengeId, selectedMode]);

  useEffect(() => {
    return () => {
      const snapshot = latestSnapshotRef.current;
      const lastPersistedDrafts = lastPersistedDraftsRef.current;
      const hasUnflushedDrafts = hasSessionSnapshotChanges(
        snapshot,
        lastPersistedDrafts,
      );

      if (!hasUnflushedDrafts) {
        return;
      }

      debugLog("session", "flushing session snapshot before challenge switch", {
        challengeId: snapshot.challengeId,
      });

      void persistSnapshot(snapshot, {}, { broadcast: false });
    };
  }, [persistSnapshot, resolvedChallengeId]);

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

    if (persistTimeoutRef.current) {
      clearTimeout(persistTimeoutRef.current);
    }

    persistTimeoutRef.current = setTimeout(() => {
      debugLog("session", "persisting draft snapshot", {
        challengeId: resolvedChallengeId,
        notesLength: notesDraft.length,
        assistantLength: assistantDraft.length,
      });
      void persistSnapshot(
        latestSnapshotRef.current,
        {
          notesDraft,
          assistantDraft,
        },
        { broadcast: false },
      );
      persistTimeoutRef.current = null;
    }, 400);

    return () => {
      if (persistTimeoutRef.current) {
        clearTimeout(persistTimeoutRef.current);
        persistTimeoutRef.current = null;
      }
    };
  }, [assistantDraft, notesDraft, persistSnapshot, resolvedChallengeId]);

  useEffect(() => {
    return () => {
      if (persistTimeoutRef.current) {
        clearTimeout(persistTimeoutRef.current);
        persistTimeoutRef.current = null;
      }

      const snapshot = latestSnapshotRef.current;
      const lastPersistedDrafts = lastPersistedDraftsRef.current;
      const hasUnflushedDrafts = hasSessionSnapshotChanges(
        snapshot,
        lastPersistedDrafts,
      );

      if (!hasUnflushedDrafts) {
        return;
      }

      debugLog("session", "flushing session snapshot during cleanup", {
        challengeId: snapshot.challengeId,
      });

      void persistSnapshot(snapshot, {}, { broadcast: false });
    };
  }, [persistSnapshot]);

  return {
    persistSession,
    syncPersistedDraftSnapshot,
  };
}
