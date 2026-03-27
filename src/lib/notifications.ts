import * as Notifications from "expo-notifications";
import { router } from "expo-router";

import { debugLog } from "@/lib/debug";
import { buildDailyReminderPlan, DAILY_REMINDER_IDENTIFIER } from "@/lib/notification-plan";
import {
  ensureDefaultSettings,
  getCurrentActiveChallenge,
} from "@/lib/storage/repository";

const DRILLBIT_NOTIFICATION_CHANNEL_ID = "drillbit-reminders";

type SyncNotificationOptions = {
  requestPermissionsIfNeeded?: boolean;
};

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowBanner: true,
    shouldShowList: true,
    shouldPlaySound: false,
    shouldSetBadge: false,
  }),
});

async function ensureNotificationChannelAsync() {
  await Notifications.setNotificationChannelAsync(DRILLBIT_NOTIFICATION_CHANNEL_ID, {
    name: "Drill reminders",
    importance: Notifications.AndroidImportance.DEFAULT,
    sound: null,
    vibrationPattern: [0],
    enableVibrate: false,
  });
}

function hasGrantedNotificationPermission(
  settings: Notifications.NotificationPermissionsStatus,
) {
  return (
    settings.granted ||
    settings.ios?.status === Notifications.IosAuthorizationStatus.PROVISIONAL
  );
}

export async function cancelDrillbitNotifications() {
  const scheduled = await Notifications.getAllScheduledNotificationsAsync();
  const drillbitReminderIds = scheduled
    .filter((request) => request.identifier === DAILY_REMINDER_IDENTIFIER)
    .map((request) => request.identifier);

  await Promise.all(
    drillbitReminderIds.map((identifier) =>
      Notifications.cancelScheduledNotificationAsync(identifier),
    ),
  );
}

export async function syncChallengeNotifications(
  options: SyncNotificationOptions = {},
) {
  const settings = await ensureDefaultSettings();
  const activeChallenge = await getCurrentActiveChallenge();
  const plan = buildDailyReminderPlan({
    settings,
    activeChallenge,
  });

  if (!plan) {
    await cancelDrillbitNotifications();
    return { enabled: false, permissionGranted: false };
  }

  await ensureNotificationChannelAsync();

  let permissions = await Notifications.getPermissionsAsync();
  if (
    !hasGrantedNotificationPermission(permissions) &&
    options.requestPermissionsIfNeeded
  ) {
    permissions = await Notifications.requestPermissionsAsync();
  }

  if (!hasGrantedNotificationPermission(permissions)) {
    await cancelDrillbitNotifications();
    return { enabled: true, permissionGranted: false };
  }

  await cancelDrillbitNotifications();

  await Notifications.scheduleNotificationAsync({
    identifier: plan.identifier,
    content: {
      title: plan.title,
      body: plan.body,
      sound: false,
      data: {
        kind: "open-active-challenge",
      },
    },
    trigger: {
      type: Notifications.SchedulableTriggerInputTypes.DAILY,
      hour: plan.hour,
      minute: plan.minute,
      channelId: DRILLBIT_NOTIFICATION_CHANNEL_ID,
    },
  });

  debugLog("notifications", "scheduled daily reminder", plan);

  return { enabled: true, permissionGranted: true };
}

export async function handleNotificationOpen(data?: Record<string, unknown>) {
  if (data?.kind !== "open-active-challenge") {
    return;
  }

  const activeChallenge = await getCurrentActiveChallenge();
  if (!activeChallenge) {
    router.replace("/(tabs)");
    return;
  }

  router.push({
    pathname: "/answer",
    params: {
      challengeId: activeChallenge.id,
    },
  });
}
