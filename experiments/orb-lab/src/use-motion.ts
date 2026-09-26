import { useEffect, useState } from "react";
import { AccessibilityInfo, AppState } from "react-native";
import {
  runOnJS,
  useFrameCallback,
  useSharedValue,
  type SharedValue,
} from "react-native-reanimated";
import { BAND_COUNT, SILENCE, envelope } from "./spectrum";
import type { Motion } from "./orb";
export function useMotion(targets: SharedValue<number[]>, active: boolean) {
  const motion = useSharedValue<Motion>({
    phase: 0,
    bands: [...SILENCE],
    energy: 0,
  });
  const amount = useSharedValue(1);
  const release = useSharedValue(260);
  const attack = useSharedValue(45);
  const selected = useSharedValue(-1);
  const reduced = useSharedValue(false);
  const [systemReduced, setSystemReduced] = useState(false);
  const [reduceOverride, setReduceOverride] = useState(false);
  const [foreground, setForeground] = useState(
    AppState.currentState === "active",
  );
  const [metrics, setMetrics] = useState({ fps: 0, p95: 0 });
  const accumulator = useSharedValue({ ms: 0, samples: [] as number[] });
  useEffect(() => {
    let alive = true;
    void AccessibilityInfo.isReduceMotionEnabled().then((v) => {
      if (alive) setSystemReduced(v);
    });
    const sub = AccessibilityInfo.addEventListener(
      "reduceMotionChanged",
      setSystemReduced,
    );
    const app = AppState.addEventListener("change", (value) =>
      setForeground(value === "active"),
    );
    return () => {
      alive = false;
      sub.remove();
      app.remove();
    };
  }, []);
  const reduceMotion = systemReduced || reduceOverride;
  useEffect(() => {
    reduced.value = reduceMotion;
  }, [reduceMotion, reduced]);
  const callback = useFrameCallback((info) => {
    const ms = info.timeSincePreviousFrame ?? 16.667;
    const dt = Math.min(ms / 1000, 0.05);
    const old = motion.value;
    const bands = old.bands.map((v, i) =>
      envelope(v, targets.value[i] || 0, dt, attack.value, release.value),
    );
    const energy = bands.reduce((sum, value) => sum + value, 0) / BAND_COUNT;
    // Accessibility mode freezes geometry, without hiding the real FFT meters in the UI.
    motion.value = reduced.value
      ? { ...old, bands: SILENCE, energy: 0 }
      : { phase: old.phase + dt * 0.44, bands, energy };
    const sample = accumulator.value;
    sample.ms += ms;
    sample.samples.push(ms);
    if (sample.ms >= 1000) {
      const sorted = [...sample.samples].sort((a, b) => a - b);
      runOnJS(setMetrics)({
        fps: Math.round((sample.samples.length * 1000) / sample.ms),
        p95: Math.round(sorted[Math.floor(sorted.length * 0.95)] * 10) / 10,
      });
      accumulator.value = { ms: 0, samples: [] };
    }
  });
  useEffect(() => {
    callback.setActive(active && foreground);
    return () => callback.setActive(false);
  }, [active, foreground, callback]);
  return {
    motion,
    amount,
    release,
    attack,
    selected,
    reduceMotion,
    reduceOverride,
    setReduceOverride,
    systemReduced,
    metrics,
  };
}
