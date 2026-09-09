import "../../global.css";

import { Stack, usePathname, useSegments } from "expo-router";
import { StatusBar } from "expo-status-bar";
import * as SystemUI from "expo-system-ui";
import { HeroUINativeProvider } from "heroui-native";
import type { PropsWithChildren } from "react";
import { useEffect, useState } from "react";
import { LogBox, Platform, useColorScheme, View } from "react-native";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import { SafeAreaListener, SafeAreaProvider } from "react-native-safe-area-context";
import { Uniwind } from "uniwind";

import { APP_THEME_COLORS } from "@/constants/theme";
import { debugLog } from "@/lib/debug";
import { retryMissingChallengeSummaries } from "@/lib/memory-sync";
import { syncChallengeNotifications, handleNotificationOpen } from "@/lib/notifications";
import { initializePromptLibrary } from "@/lib/prompts/prompt-library";
import { subscribeToChallengeRefresh } from "@/lib/challenge-refresh";
import { addDrillbitWidgetInteractionListener } from "@/lib/widgets/interaction";
import { subscribeToSettingsRefresh } from "@/lib/settings-refresh";
import { syncWidgetState } from "@/lib/widgets/sync";

const IGNORED_NATIVE_VIEW_ERRORS = [
  "could not find view or tag",
  "could not find view for tag",
  "Uncaught (in promise, id:",
];

const IGNORED_WEB_STYLEQ_ERRORS = [
  'styleq: left typeof 0 is not "string" or "null".',
  'styleq: right typeof 0 is not "string" or "null".',
  'styleq: top typeof 0 is not "string" or "null".',
  'styleq: bottom typeof 0 is not "string" or "null".',
];

function NativeKeyboardBoundary({ children }: PropsWithChildren) {
  const [KeyboardProvider, setKeyboardProvider] = useState<
    typeof import("react-native-keyboard-controller").KeyboardProvider | null
  >(null);

  useEffect(() => {
    if (Platform.OS === "web") {
      return;
    }

    let isMounted = true;

    void import("react-native-keyboard-controller").then((module) => {
      if (isMounted) {
        setKeyboardProvider(() => module.KeyboardProvider);
      }
    });

    return () => {
      isMounted = false;
    };
  }, []);

  if (Platform.OS === "web") {
    return <>{children}</>;
  }

  if (!KeyboardProvider) {
    return <>{children}</>;
  }

  return <KeyboardProvider preload={false}>{children}</KeyboardProvider>;
}

export default function RootLayout() {
  const colorScheme = useColorScheme();
  const isDark = colorScheme !== "light";
  const resolvedTheme = colorScheme === "light" || colorScheme === "dark" ? colorScheme : "system";
  const pathname = usePathname();
  const segments = useSegments();

  useEffect(() => {
    LogBox.ignoreLogs([
      "Sending `onAnimatedValueUpdate` with no listeners registered.",
      "could not find view or tag",
      "could not find view for tag",
      "Uncaught (in promise, id:",
    ]);
  }, []);

  useEffect(() => {
    const originalConsoleError = console.error;

    console.error = (...args: unknown[]) => {
      const firstArg = typeof args[0] === "string" ? args[0] : "";
      const shouldIgnoreNativeViewError = IGNORED_NATIVE_VIEW_ERRORS.some(
        (message) => firstArg.includes(message),
      );
      const shouldIgnoreWebStyleqError =
        Platform.OS === "web" &&
        IGNORED_WEB_STYLEQ_ERRORS.some((message) => firstArg.includes(message));

      if (shouldIgnoreNativeViewError || shouldIgnoreWebStyleqError) {
        return;
      }

      originalConsoleError(...args);
    };

    return () => {
      console.error = originalConsoleError;
    };
  }, []);

  useEffect(() => {
    Uniwind.setTheme(resolvedTheme);
    void SystemUI.setBackgroundColorAsync(
      isDark ? APP_THEME_COLORS.darkBackground : APP_THEME_COLORS.lightBackground,
    );
    void initializePromptLibrary();
    void syncWidgetState();
    void retryMissingChallengeSummaries();
    void syncChallengeNotifications();
  }, [isDark, resolvedTheme]);

  useEffect(() => {
    return subscribeToSettingsRefresh(() => {
      void syncChallengeNotifications();
    });
  }, []);

  useEffect(() => {
    return subscribeToChallengeRefresh(() => {
      void syncChallengeNotifications();
    });
  }, []);

  useEffect(() => {
    debugLog("router", "route changed", {
      pathname,
      segments,
    });
  }, [pathname, segments]);

  useEffect(() => {
    let subscription: { remove: () => void } | null = null;
    let isMounted = true;

    void addDrillbitWidgetInteractionListener().then((nextSubscription) => {
      if (!isMounted) {
        nextSubscription.remove();
        return;
      }

      subscription = nextSubscription;
    });

    return () => {
      isMounted = false;
      subscription?.remove();
    };
  }, []);

  useEffect(() => {
    if (Platform.OS === "web") {
      return;
    }

    let subscription: { remove: () => void } | null = null;
    let isMounted = true;

    void import("expo-notifications").then((Notifications) => {
      if (!isMounted) {
        return;
      }

      subscription = Notifications.addNotificationResponseReceivedListener((response) => {
        void handleNotificationOpen(
          (response.notification.request.content.data ?? {}) as Record<string, unknown>,
        );
      });

      void Notifications.getLastNotificationResponseAsync().then((response) => {
        if (!response) {
          return;
        }

        void handleNotificationOpen(
          (response.notification.request.content.data ?? {}) as Record<string, unknown>,
        );
      });
    });

    return () => {
      isMounted = false;
      subscription?.remove();
    };
  }, []);

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <SafeAreaProvider>
        <SafeAreaListener
          style={{ flex: 1 }}
          onChange={({ insets }) => {
            Uniwind.updateInsets(insets);
          }}
        >
          <NativeKeyboardBoundary>
            <HeroUINativeProvider config={{ devInfo: { stylingPrinciples: false } }}>
              <View className="flex-1 bg-background">
                <StatusBar style={isDark ? "light" : "dark"} />
                <Stack
                  screenOptions={{
                    headerShown: false,
                    contentStyle: { backgroundColor: "transparent" },
                  }}
                >
                  <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
                  <Stack.Screen
                    name="answer"
                    options={{
                      headerShown: false,
                      contentStyle: { backgroundColor: "transparent" },
                    }}
                  />
                </Stack>
              </View>
            </HeroUINativeProvider>
          </NativeKeyboardBoundary>
        </SafeAreaListener>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}
