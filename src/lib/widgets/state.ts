import { debugLog } from "@/lib/debug";
import {
  ensureDefaultSettings,
  getChallengeSession,
  getCurrentActiveChallenge,
  getMostRecentResolvedChallenge,
} from "@/lib/storage/repository";
import { formatTimeMinutes, getNextScheduledChallengeDate } from "@/lib/time";
import {
  createPlaceholderWidgetState,
  type WidgetViewState,
} from "@/lib/widgets/types";

function getAwaitingNextDetail(nextRefreshAt: string) {
  const nextDate = new Date(nextRefreshAt);
  const isValid = !Number.isNaN(nextDate.getTime());

  if (!isValid) {
    return "You are clear for now. A fresh challenge will arrive on your schedule.";
  }

  const today = new Date();
  const isSameDay = nextDate.toDateString() === today.toDateString();
  const label = formatTimeMinutes(nextDate.getHours() * 60 + nextDate.getMinutes());

  return isSameDay
    ? `You are clear for now. Next challenge arrives today at ${label}.`
    : `You are clear for now. Next challenge arrives at ${label}.`;
}

export async function buildWidgetViewState(): Promise<WidgetViewState> {
  try {
    const [settings, activeChallenge, lastResolvedChallenge] = await Promise.all([
      ensureDefaultSettings(),
      getCurrentActiveChallenge(),
      getMostRecentResolvedChallenge(),
    ]);
    const activeSession = activeChallenge
      ? await getChallengeSession(activeChallenge.id)
      : null;
    const preferredMode =
      activeSession?.selectedMode ?? settings.preferredMode ?? "solo";

    if (!settings.selectedModelId) {
      return {
        status: "unconfigured",
        title: "Finish setup",
        detail: "Pick a model and tune your prompt before the widget starts serving challenges.",
        cta: "Open params",
      };
    }

    if (activeChallenge?.lifecycle === "in_progress") {
      return {
        status: "in_progress",
        title: activeChallenge.title,
        detail: activeChallenge.teaser,
        cta: `Resume ${preferredMode}`,
        preferredMode,
        challenge: activeChallenge,
      };
    }

    if (activeChallenge?.lifecycle === "ready") {
      return {
        status: "ready",
        title: activeChallenge.title,
        detail: activeChallenge.teaser,
        cta: `Open ${preferredMode}`,
        preferredMode,
        challenge: activeChallenge,
      };
    }

    const nextRefreshAt = getNextScheduledChallengeDate({
      firstChallengeTimeMinutes: settings.firstChallengeTimeMinutes ?? 9 * 60,
      challengeCadenceHours: settings.challengeCadenceHours ?? 24,
    }).toISOString();

    return {
      status: "awaiting_next",
      title: "All clear",
      detail: getAwaitingNextDetail(nextRefreshAt),
      cta: "Open memory",
      lastResolvedChallenge: lastResolvedChallenge ?? undefined,
      nextRefreshAt,
    };
  } catch (error) {
    debugLog("widget", "failed to build widget state", error);

    return {
      ...createPlaceholderWidgetState(),
      status: "error",
      title: "Widget unavailable",
      detail: "Open drillbit to refresh local widget state.",
      cta: "Open app",
      message: error instanceof Error ? error.message : "Unknown widget error",
    };
  }
}
