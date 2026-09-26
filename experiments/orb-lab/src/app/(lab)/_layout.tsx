import { Stack } from "expo-router";
import { useLabTheme } from "../../theme";
export default function Layout() {
  const { colors } = useLabTheme();
  return (
    <Stack
      screenOptions={{
        headerStyle: { backgroundColor: colors.bg },
        headerTintColor: colors.ink,
        headerShadowVisible: false,
        contentStyle: { backgroundColor: colors.bg },
      }}
    >
      <Stack.Screen name="index" options={{ title: "Orb Lab" }} />
    </Stack>
  );
}
