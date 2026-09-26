import React, { memo } from "react";
import {
  Canvas,
  Circle,
  Path,
  Skia,
} from "@shopify/react-native-skia";
import {
  useDerivedValue,
  withTiming,
  type SharedValue,
} from "react-native-reanimated";
import { BAND_COUNT } from "./spectrum";

export type Motion = { phase: number; bands: number[]; energy: number };
const POINTS = 96;
const ANGLES = Array.from(
  { length: POINTS + 1 },
  (_, i) => (i * Math.PI * 2) / POINTS,
);
const COS = ANGLES.map(Math.cos);
const SIN = ANGLES.map(Math.sin);

const Contour = memo(function Contour({
  index,
  size,
  motion,
  amount,
  selected,
}: {
  index: number;
  size: number;
  motion: SharedValue<Motion>;
  amount: SharedValue<number>;
  selected: SharedValue<number>;
}) {
  const path = useDerivedValue(() => {
    const result = Skia.PathBuilder.Make();
    const { phase, bands, energy } = motion.value;
    const scale = size / 320;
    const center = size / 2;
    const level = bands[index] || 0;
    const radius =
      (53 +
        index * 6.2 +
        energy * 5 * amount.value +
        level * 5 * amount.value) *
      scale;
    for (let j = 0; j <= POINTS; j++) {
      const angle = ANGLES[j];
      // Shared phase keeps the shell coherent. Each band's energy changes depth, not tempo.
      const wave =
        Math.sin(angle * 3 + phase + index * 0.19) *
          (3 + level * 5 * amount.value) +
        Math.sin(angle * 2 - phase * 0.71 + index * 0.12) * (2 + energy * 2) +
        Math.sin(angle * 5 + phase * 0.4 + index * 0.14) *
          level *
          1.5 *
          amount.value;
      const r = radius + wave * scale;
      const x = center + COS[j] * r;
      const y = center + SIN[j] * r * (0.96 + 0.025 * Math.sin(phase * 0.32));
      if (j === 0) result.moveTo(x, y);
      else result.lineTo(x, y);
    }
    result.close();
    return result.build();
  });
  const focusOpacity = useDerivedValue(() =>
    withTiming(selected.value >= 0 && selected.value !== index ? 0.16 : 1, {
      duration: 160,
    }),
  );
  const opacity = useDerivedValue(
    () =>
      focusOpacity.value *
      (0.52 + index * 0.027 + motion.value.bands[index] * 0.16),
  );
  return (
    <Path
      path={path}
      style="stroke"
      strokeWidth={1.1}
      color="#FFD071"
      opacity={opacity}
    />
  );
});

export const Orb = memo(function Orb({
  size,
  motion,
  amount,
  selected,
}: {
  size: number;
  motion: SharedValue<Motion>;
  amount: SharedValue<number>;
  selected: SharedValue<number>;
}) {
  const coreRadius = useDerivedValue(
    () => ((3.5 + motion.value.energy * 2.5) * size) / 320,
  );
  return (
    <Canvas style={{ width: size, height: size }} accessible={false}>
      <Circle
        cx={size / 2}
        cy={size / 2}
        r={size * 0.455}
        color="#232834"
      />
      {Array.from({ length: BAND_COUNT }, (_, i) => (
        <Contour
          key={i}
          index={i}
          size={size}
          motion={motion}
          amount={amount}
          selected={selected}
        />
      ))}
      <Circle cx={size / 2} cy={size / 2} r={coreRadius} color="#FFCC65" />
    </Canvas>
  );
});
