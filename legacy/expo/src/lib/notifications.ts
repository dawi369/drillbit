import { router } from "expo-router";
import { Platform } from "react-native";

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

type NotificationsModule = typeof import("expo-notifications");
type NotificationPermissionsStatus =
  import("expo-notifications").NotificationPermissionsStatus;

const canUseNativeNotifications = Platform.OS !== "web";
let hasConfiguredNotificationHandler = false;

async function getNotificationsModule() {
  if (!canUseNativeNotifications) {
    return null;
  }

  return import("expo-notifications");
}

function configureNotificationHandler(notifications: NotificationsModule) {
  if (hasConfiguredNotificationHandler) {
    return;
  }

  notifications.setNotificationHandler({
    handleNotification: async () => ({
      shouldShowBanner: true,
      shouldShowList: true,
      shouldPlaySound: false,
      shouldSetBadge: false,
    }),
  });

  hasConfiguredNotificationHandler = true;
}

async function ensureNotificationChannelAsync(
  notifications: NotificationsModule,
) {
  await notifications.setNotificationChannelAsync(DRILLBIT_NOTIFICATION_CHANNEL_ID, {
    name: "Drill reminders",
    importance: notifications.AndroidImportance.DEFAULT,
    sound: null,
    vibrationPattern: [0],
    enableVibrate: false,
  });
}

function hasGrantedNotificationPermission(
  notifications: NotificationsModule,
  settings: NotificationPermissionsStatus,
) {
  return (
    settings.granted ||
    settings.ios?.status === notifications.IosAuthorizationStatus.PROVISIONAL
  );
}

export async function cancelDrillbitNotifications() {
  const notifications = await getNotificationsModule();
  if (!notifications) {
    return;
  }

  const scheduled = await notifications.getAllScheduledNotificationsAsync();
  const drillbitReminderIds = scheduled
    .filter((request) => request.identifier === DAILY_REMINDER_IDENTIFIER)
    .map((request) => request.identifier);

  await Promise.all(
    drillbitReminderIds.map((identifier) =>
      notifications.cancelScheduledNotificationAsync(identifier),
    ),
  );
}

export async function syncChallengeNotifications(
  options: SyncNotificationOptions = {},
) {
  const notifications = await getNotificationsModule();
  if (!notifications) {
    return { enabled: false, permissionGranted: false };
  }

  configureNotificationHandler(notifications);

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

  await ensureNotificationChannelAsync(notifications);

  let permissions = await notifications.getPermissionsAsync();
  if (
    !hasGrantedNotificationPermission(notifications, permissions) &&
    options.requestPermissionsIfNeeded
  ) {
    permissions = await notifications.requestPermissionsAsync();
  }

  if (!hasGrantedNotificationPermission(notifications, permissions)) {
    await cancelDrillbitNotifications();
    return { enabled: true, permissionGranted: false };
  }

  await cancelDrillbitNotifications();

  await notifications.scheduleNotificationAsync({
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
      type: notifications.SchedulableTriggerInputTypes.DAILY,
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
