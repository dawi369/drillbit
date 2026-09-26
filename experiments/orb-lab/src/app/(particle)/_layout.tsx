import { Stack } from "expo-router";
import { particlePalette as color } from "../../particle-palette";

export default function ParticleLayout() {
  return (
    <Stack
      screenOptions={{
        headerShown: false,
        contentStyle: { backgroundColor: color.top },
      }}
    />
  );
}
