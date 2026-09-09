import { formatTimeMinutes } from "@/lib/time";
import type { ChallengeRecord, UserSettingsRecord } from "@/lib/storage/types";

export type DailyReminderPlan = {
  identifier: string;
  hour: number;
  minute: number;
  title: string;
  body: string;
};

export const DAILY_REMINDER_IDENTIFIER = "daily-challenge-reminder";

export function buildDailyReminderPlan({
  settings,
  activeChallenge,
}: {
  settings: UserSettingsRecord;
  activeChallenge?: ChallengeRecord | null;
}): DailyReminderPlan | null {
  if (!settings.notificationsEnabled || !settings.selectedModelId) {
    return null;
  }

  if (activeChallenge?.lifecycle === "in_progress") {
    return null;
  }

  const totalMinutes = settings.firstChallengeTimeMinutes ?? 9 * 60;
  const hour = Math.floor(totalMinutes / 60);
  const minute = totalMinutes % 60;

  if (activeChallenge?.lifecycle === "ready") {
    return {
      identifier: DAILY_REMINDER_IDENTIFIER,
      hour,
      minute,
      title: "today's drill is ready",
      body: activeChallenge.title,
    };
  }

  return {
    identifier: DAILY_REMINDER_IDENTIFIER,
    hour,
    minute,
    title: "time for a drillbit rep",
    body: `One quiet reminder at ${formatTimeMinutes(totalMinutes)}. Open drillbit when you have a focused block.`,
  };
}
