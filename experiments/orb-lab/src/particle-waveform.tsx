import React, { memo } from "react";
import { Canvas, Path, Skia } from "@shopify/react-native-skia";
import { useDerivedValue, type SharedValue } from "react-native-reanimated";
import type { Motion } from "./orb";
import { particlePalette as color } from "./particle-palette";

const WIDTH = 156;
const HEIGHT = 32;
const BARS = 31;

export const ParticleWaveform = memo(function ParticleWaveform({
  motion,
}: {
  motion: SharedValue<Motion>;
}) {
  const dots = useDerivedValue(() => {
    const path = Skia.PathBuilder.Make();
    for (let i = 0; i < BARS; i++) {
      const x = 4 + (i * (WIDTH - 8)) / (BARS - 1);
      const band = Math.min(11, Math.floor((i / BARS) * 12));
      const level = motion.value.bands[band] || 0;
      const accented = (i >= 3 && i <= 5) || (i >= 25 && i <= 27);
      const idleAccent = accented ? (i % 2 ? 5 : 9) : 0;
      const height = 1.8 + idleAccent + level * 19;
      if (height < 3) {
        path.addCircle(x, HEIGHT / 2, 1.1);
      } else {
        path.moveTo(x, (HEIGHT - height) / 2);
        path.lineTo(x, (HEIGHT + height) / 2);
      }
    }
    return path.build();
  });

  return (
    <Canvas style={{ width: WIDTH, height: HEIGHT }} accessible={false}>
      <Path
        path={dots}
        style="stroke"
        strokeWidth={2}
        strokeCap="round"
        color={color.label}
        opacity={0.78}
      />
    </Canvas>
  );
});
