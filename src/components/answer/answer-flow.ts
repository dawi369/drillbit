import type {
  ChallengeConversationTurn,
  CoachTriggerReason,
} from "@/lib/storage/types";
import type { ChallengeMode } from "@/lib/widgets/types";

export const AUTO_COACH_MIN_NOTES_CHARS = 126;
export const AUTO_COACH_MIN_NEW_CHARS = 56;
export const AUTO_COACH_IDLE_MS = 2500;
export const AUTO_COACH_COOLDOWN_MS = 15000;

type SessionSnapshotLike = {
  challengeId: string | null;
  selectedMode: ChallengeMode;
  notesDraft: string;
  assistantDraft: string;
  conversationHistory: ChallengeConversationTurn[];
};

export function normalizeCoachText(value: string) {
  return value.trim().replace(/\s+/g, " ");
}

export function resolveAnswerMode({
  routeMode,
  sessionMode,
  preferredMode,
}: {
  routeMode: ChallengeMode | null;
  sessionMode?: ChallengeMode;
  preferredMode?: ChallengeMode;
}) {
  return routeMode ?? sessionMode ?? preferredMode ?? "solo";
}

export function getAssistantThreadMode(mode: ChallengeMode) {
  return mode === "reveal" ? "reveal" : "coach";
}

export function hasSessionSnapshotChanges(
  snapshot: SessionSnapshotLike,
  lastPersistedDrafts: SessionSnapshotLike,
) {
  return (
    snapshot.challengeId != null &&
    snapshot.challengeId === lastPersistedDrafts.challengeId &&
    (snapshot.notesDraft !== lastPersistedDrafts.notesDraft ||
      snapshot.assistantDraft !== lastPersistedDrafts.assistantDraft ||
      snapshot.selectedMode !== lastPersistedDrafts.selectedMode ||
      snapshot.conversationHistory !== lastPersistedDrafts.conversationHistory)
  );
}

export function getAutoCoachTriggerReason({
  selectedMode,
  resolvedChallengeId,
  hasChallenge,
  isCoachLoading,
  normalizedNotesDraft,
  conversationHistory,
  lastAutoCoachAt,
  lastAutoCoachNotesSnapshot,
  now = Date.now(),
}: {
  selectedMode: ChallengeMode;
  resolvedChallengeId: string | null;
  hasChallenge: boolean;
  isCoachLoading: boolean;
  normalizedNotesDraft: string;
  conversationHistory: ChallengeConversationTurn[];
  lastAutoCoachAt: number | null;
  lastAutoCoachNotesSnapshot: string;
  now?: number;
}): CoachTriggerReason | null {
  if (selectedMode !== "coach") {
    return null;
  }

  if (!resolvedChallengeId || !hasChallenge || isCoachLoading) {
    return null;
  }

  const noteLength = normalizedNotesDraft.length;
  if (noteLength < AUTO_COACH_MIN_NOTES_CHARS) {
    return null;
  }

  const lastCoachTurn = [...conversationHistory]
    .reverse()
    .find((turn) => turn.role === "assistant" && turn.mode === "coach");
  const trigger: CoachTriggerReason = lastCoachTurn
    ? "auto_after_progress"
    : "auto_initial";

  if (
    trigger === "auto_after_progress" &&
    Math.max(0, noteLength - lastAutoCoachNotesSnapshot.length) <
      AUTO_COACH_MIN_NEW_CHARS
  ) {
    return null;
  }

  if (lastAutoCoachAt != null && now - lastAutoCoachAt < AUTO_COACH_COOLDOWN_MS) {
    return null;
  }

  return trigger;
}
