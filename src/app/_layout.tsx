import "../../global.css";

import { Stack, usePathname, useSegments } from "expo-router";
import { StatusBar } from "expo-status-bar";
import * as SystemUI from "expo-system-ui";
import { HeroUINativeProvider } from "heroui-native";
import { useEffect } from "react";
import { LogBox, useColorScheme } from "react-native";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import { KeyboardProvider } from "react-native-keyboard-controller";
import { SafeAreaListener, SafeAreaProvider } from "react-native-safe-area-context";
import { Uniwind } from "uniwind";

import { debugLog } from "@/lib/debug";
import { initializePromptLibrary } from "@/lib/prompts/prompt-library";

export default function RootLayout() {
  const colorScheme = useColorScheme();
  const isDark = colorScheme !== "light";
  const resolvedTheme = colorScheme === "light" || colorScheme === "dark" ? colorScheme : "system";
  const pathname = usePathname();
  const segments = useSegments();

  useEffect(() => {
    LogBox.ignoreLogs([
      "Sending `onAnimatedValueUpdate` with no listeners registered.",
    ]);
  }, []);

  useEffect(() => {
    Uniwind.setTheme(resolvedTheme);
    void SystemUI.setBackgroundColorAsync(isDark ? "#000000" : "#ffffff");
    void initializePromptLibrary();
  }, [isDark, resolvedTheme]);

  useEffect(() => {
    debugLog("router", "route changed", {
      pathname,
      segments,
    });
  }, [pathname, segments]);

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <SafeAreaProvider>
        <SafeAreaListener
          style={{ flex: 1 }}
          onChange={({ insets }) => {
            Uniwind.updateInsets(insets);
          }}
        >
          <KeyboardProvider preload={false}>
            <HeroUINativeProvider config={{ devInfo: { stylingPrinciples: false } }}>
              <StatusBar style={isDark ? "light" : "dark"} />
              <Stack
                screenOptions={{
                  headerShown: false,
                  contentStyle: { backgroundColor: isDark ? "#000000" : "#ffffff" },
                }}
              >
                <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
                <Stack.Screen
                  name="answer"
                  options={{
                    headerShown: false,
                    contentStyle: { backgroundColor: isDark ? "#000000" : "#ffffff" },
                  }}
                />
              </Stack>
            </HeroUINativeProvider>
          </KeyboardProvider>
        </SafeAreaListener>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}
