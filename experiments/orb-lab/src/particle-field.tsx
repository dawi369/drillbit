import React, { memo, useMemo } from "react";
import { Canvas, Path, Skia } from "@shopify/react-native-skia";
import { useDerivedValue, type SharedValue } from "react-native-reanimated";
import type { Motion } from "./orb";
import { particlePalette as color } from "./particle-palette";

type Particle = {
  x: number;
  y: number;
  radius: number;
  band: number;
  angle: number;
  seed: number;
};

function random(seed: number) {
  let state = seed >>> 0;
  return () => {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state / 4294967296;
  };
}

function makeParticles(count: number, seed: number): Particle[] {
  const next = random(seed);
  const result: Particle[] = [];
  for (let i = 0; i < count; i++) {
    // Gaussian placement creates a dense nucleus and naturally sparse edges.
    const a = next() * Math.PI * 2;
    const r = Math.min(
      1.15,
      Math.sqrt(-2 * Math.log(Math.max(next(), 0.00001))) * 0.4,
    );
    const x = Math.cos(a) * r;
    const y = Math.sin(a) * r * 0.82;
    result.push({
      x,
      y,
      radius: 0.22 + next() * 0.42,
      band: Math.min(11, Math.floor(Math.min(0.999, r / 1.15) * 12)),
      angle: a,
      seed: next() * Math.PI * 2,
    });
  }
  return result;
}

function staticPath(particles: Particle[], size: number) {
  const path = Skia.PathBuilder.Make();
  const center = size / 2;
  const scale = size * 0.43;
  for (const p of particles) {
    path.addCircle(center + p.x * scale, center + p.y * scale, p.radius);
  }
  return path.build();
}

const farParticles = makeParticles(2600, 0x1570);
const nearParticles = makeParticles(3000, 0x7192);
const liveParticles = makeParticles(650, 0x3430);

export const ParticleField = memo(function ParticleField({
  size,
  motion,
}: {
  size: number;
  motion: SharedValue<Motion>;
}) {
  const far = useMemo(() => staticPath(farParticles, size), [size]);
  const near = useMemo(() => staticPath(nearParticles, size), [size]);
  const live = useDerivedValue(() => {
    const path = Skia.PathBuilder.Make();
    const { phase, bands, energy } = motion.value;
    const center = size / 2;
    const scale = size * 0.43;
    for (const p of liveParticles) {
      const band = bands[p.band] || 0;
      const pulse = 1 + energy * 0.1 + band * 0.22;
      const drift = Math.sin(phase * 1.8 + p.seed) * (0.9 + band * 5);
      const x = center + p.x * scale * pulse + Math.cos(p.angle) * drift;
      const y = center + p.y * scale * pulse + Math.sin(p.angle) * drift * 0.8;
      path.addCircle(x, y, p.radius + band * 0.33);
    }
    return path.build();
  });
  const liveOpacity = useDerivedValue(
    () => 0.56 + Math.min(0.32, motion.value.energy * 0.55),
  );

  return (
    <Canvas style={{ width: size, height: size }} accessible={false}>
      <Path path={far} color={color.distant} opacity={0.34} />
      <Path path={near} color={color.particle} opacity={0.49} />
      <Path path={live} color={color.white} opacity={liveOpacity} />
    </Canvas>
  );
});
