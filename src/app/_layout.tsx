import "../../global.css";

import { Stack } from "expo-router";
import { StatusBar } from "expo-status-bar";
import * as SystemUI from "expo-system-ui";
import { HeroUINativeProvider } from "heroui-native";
import { useEffect } from "react";
import { useColorScheme } from "react-native";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import { SafeAreaListener, SafeAreaProvider } from "react-native-safe-area-context";
import { Uniwind } from "uniwind";

export default function RootLayout() {
  const colorScheme = useColorScheme();
  const isDark = colorScheme !== "light";

  useEffect(() => {
    Uniwind.setTheme(colorScheme ?? "system");
    void SystemUI.setBackgroundColorAsync(isDark ? "#000000" : "#ffffff");
  }, [colorScheme, isDark]);

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <SafeAreaProvider>
        <SafeAreaListener
          style={{ flex: 1 }}
          onChange={({ insets }) => {
            Uniwind.updateInsets(insets);
          }}
        >
          <HeroUINativeProvider>
            <StatusBar style={isDark ? "light" : "dark"} />
            <Stack
              screenOptions={{
                headerShown: false,
                contentStyle: { backgroundColor: isDark ? "#000000" : "#ffffff" },
              }}
            />
          </HeroUINativeProvider>
        </SafeAreaListener>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}
