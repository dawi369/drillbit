import React, { useCallback, useState } from "react";
import {
  Alert,
  Pressable,
  ScrollView,
  StyleSheet,
  Switch,
  Text,
  View,
  useWindowDimensions,
} from "react-native";
import { Stack, useFocusEffect } from "expo-router";
import { StatusBar } from "expo-status-bar";
import * as DocumentPicker from "expo-document-picker";
import Slider from "@react-native-community/slider";
import { VoiceOrb } from "expo-thinking-orbs";
import { useDerivedValue } from "react-native-reanimated";
import { Orb } from "../../orb";
import { SpectrumMeter } from "../../spectrum-meter";
import { useAudio, clips, type Clip } from "../../use-audio";
import { useMotion } from "../../use-motion";
import { useLabTheme } from "../../theme";
import { BAND_EDGES, frequencyLabel } from "../../spectrum";
import { brand } from "../../palette";

function Button({
  title,
  onPress,
  selected = false,
  disabled = false,
  label,
}: {
  title: string;
  onPress: () => void;
  selected?: boolean;
  disabled?: boolean;
  label?: string;
}) {
  const { colors } = useLabTheme();
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label || title}
      accessibilityState={{ selected, disabled }}
      disabled={disabled}
      onPress={onPress}
      style={({ pressed }) => [
        styles.button,
        {
          backgroundColor: selected
            ? colors.selected
            : pressed
              ? colors.surface
              : "transparent",
          borderColor: selected ? colors.accent : colors.line,
          opacity: disabled ? 0.4 : pressed ? 0.8 : 1,
        },
      ]}
    >
      <Text
        style={{
          color: selected ? colors.accent : colors.muted,
          fontSize: 14,
          fontWeight: "600",
        }}
      >
        {title}
      </Text>
    </Pressable>
  );
}
function Dial({
  label,
  value,
  min,
  max,
  format,
  onChange,
}: {
  label: string;
  value: number;
  min: number;
  max: number;
  format: (v: number) => string;
  onChange: (v: number) => void;
}) {
  const { colors } = useLabTheme();
  return (
    <View style={{ gap: 4 }}>
      <View style={styles.row}>
        <Text style={{ color: colors.ink, fontSize: 15 }}>{label}</Text>
        <Text style={[styles.mono, { color: colors.muted }]}>
          {format(value)}
        </Text>
      </View>
      <Slider
        accessibilityLabel={label}
        accessibilityValue={{ text: format(value) }}
        minimumValue={min}
        maximumValue={max}
        value={value}
        onValueChange={onChange}
        minimumTrackTintColor={colors.action}
        maximumTrackTintColor={colors.line}
        thumbTintColor={colors.action}
        style={{ height: 36 }}
      />
    </View>
  );
}
const clock = (n: number) =>
  `${Math.floor(n / 60)}:${String(Math.floor(n % 60)).padStart(2, "0")}`;

export default function Lab() {
  const { colors, mode, toggle } = useLabTheme();
  const { width, height, fontScale } = useWindowDimensions();
  const audio = useAudio();
  const stop = audio.stop;
  const [focused, setFocused] = useState(true);
  const [renderer, setRenderer] = useState<"contours" | "reference">(
    "contours",
  );
  const motion = useMotion(audio.targets, focused);
  const animatedMotion = motion.motion;
  const [clip, setClip] = useState<Clip>(clips[0]);
  const [selected, setSelected] = useState(-1);
  const [tuning, setTuning] = useState(false);
  const [volume, setVolume] = useState(0.35);
  const [sensitivity, setSensitivity] = useState(1);
  const [movement, setMovement] = useState(1);
  const [attack, setAttack] = useState(45);
  const [release, setRelease] = useState(260);
  const size = Math.min(
    width - 64,
    Math.max(200, height * (fontScale > 1.25 ? 0.25 : 0.32)),
    312,
  );
  const output = useDerivedValue(() => animatedMotion.value.energy);
  const low = useDerivedValue(() =>
    Math.max(...animatedMotion.value.bands.slice(0, 3)),
  );
  const mid = useDerivedValue(() =>
    Math.max(...animatedMotion.value.bands.slice(3, 8)),
  );
  const high = useDerivedValue(() =>
    Math.max(...animatedMotion.value.bands.slice(8)),
  );
  useFocusEffect(
    useCallback(() => {
      setFocused(true);
      return () => {
        setFocused(false);
        stop();
      };
    }, [stop]),
  );
  const choose = (next: Clip) => {
    audio.stop();
    setClip(next);
  };
  const selectBand = (next: number) => {
    setSelected(next);
    motion.selected.set(next);
  };
  const importAudio = async () => {
    audio.stop();
    try {
      const result = await DocumentPicker.getDocumentAsync({
        type: "audio/*",
        copyToCacheDirectory: true,
        multiple: false,
      });
      if (result.canceled) return;
      const file = result.assets[0];
      if (file.size && file.size > 30 * 1024 * 1024) {
        Alert.alert(
          "Clip too large",
          "Choose an audio file under 30 MB and 3 minutes.",
        );
        return;
      }
      setClip({
        id: "import",
        title: file.name,
        detail: "Local audio · stays on this device",
        asset: file.uri,
      });
    } catch {
      Alert.alert("Could not open audio", "Try another local audio file.");
    }
  };
  const playing = audio.status === "playing";
  const status = playing
    ? "Speaking"
    : audio.status === "loading"
      ? "Loading audio"
      : audio.status === "paused"
        ? "Paused"
        : "Ready when you are";
  const focusedLabel =
    selected < 0
      ? "12 frequency bands"
      : `Contour ${selected + 1} · ${frequencyLabel(BAND_EDGES[selected])}–${frequencyLabel(BAND_EDGES[selected + 1])} Hz`;
  return (
    <>
      <Stack.Screen
        options={{
          headerRight: () => (
            <Pressable
              key={`theme-${fontScale}-${mode}`}
              accessibilityRole="button"
              accessibilityLabel={`Switch to ${mode === "dark" ? "light" : "dark"} mode`}
              onPress={toggle}
              style={{
                minWidth: 48,
                minHeight: 44,
                justifyContent: "center",
                alignItems: "center",
              }}
            >
              <Text
                maxFontSizeMultiplier={1.4}
                style={{ color: colors.ink, fontSize: 14 }}
              >
                {mode === "dark" ? "Light" : "Dark"}
              </Text>
            </Pressable>
          ),
        }}
      />
      <StatusBar style={mode === "dark" ? "light" : "dark"} />
      <ScrollView
        // Remeasure native text when Dynamic Type changes while the lab is open.
        key={`type-scale-${fontScale}`}
        contentInsetAdjustmentBehavior="automatic"
        style={{ backgroundColor: colors.bg }}
        contentContainerStyle={{
          paddingHorizontal: 24,
          paddingTop: 8,
          paddingBottom: 112,
          alignItems: "center",
        }}
      >
        <View style={{ width: "100%", maxWidth: 480, gap: 16 }}>
          <View
            style={{
              flexDirection: "row",
              flexWrap: "wrap",
              justifyContent: "center",
              gap: 8,
            }}
          >
            <Button
              title="Contours"
              selected={renderer === "contours"}
              onPress={() => setRenderer("contours")}
            />
            <Button
              title="OSS reference"
              selected={renderer === "reference"}
              onPress={() => setRenderer("reference")}
            />
          </View>
          <View style={{ alignItems: "center", gap: 8 }}>
            <View
              style={{
                width: size,
                height: size,
                alignItems: "center",
                justifyContent: "center",
              }}
              accessible
              accessibilityLabel={`${renderer === "contours" ? "Drillbit contour agent" : "Open source dotted agent"}. ${status}. ${motion.reduceMotion ? "Reduced motion enabled." : ""}`}
            >
              {renderer === "contours" ? (
                <Orb
                  size={size}
                  motion={motion.motion}
                  amount={motion.amount}
                  selected={motion.selected}
                />
              ) : (
                <View
                  style={{
                    width: size * 0.91,
                    height: size * 0.91,
                    borderRadius: size,
                    backgroundColor: brand.core,
                    alignItems: "center",
                    justifyContent: "center",
                  }}
                >
                  <VoiceOrb
                    size={size * 0.88}
                    state={playing ? "speaking" : "idle"}
                    outputAmplitude={output}
                    outputLevels={{ low, mid, high }}
                    color={brand.gold}
                    theme="dark"
                    paused={motion.reduceMotion || !focused}
                  />
                </View>
              )}
            </View>
            <View
              style={{
                flexDirection: "row",
                alignItems: "center",
                justifyContent: "center",
                gap: 8,
                maxWidth: "100%",
              }}
            >
              <View
                style={{
                  width: 6,
                  height: 6,
                  borderRadius: 3,
                  backgroundColor: playing ? colors.live : colors.accent,
                }}
              />
              <Text
                accessibilityLiveRegion="polite"
                style={{
                  color: colors.ink,
                  fontSize: 23,
                  fontWeight: "500",
                  letterSpacing: -0.5,
                  flexShrink: 1,
                  textAlign: "center",
                }}
              >
                {status}
              </Text>
            </View>
            <Text style={{ color: colors.muted, fontSize: 12 }}>
              {renderer === "contours"
                ? focusedLabel
                : "expo-thinking-orbs · 3 frequency bands"}
            </Text>
          </View>
          <View style={{ gap: 8 }}>
            <SpectrumMeter
              levels={audio.targets}
              selected={selected}
              onSelect={selectBand}
            />
            <View
              style={[
                styles.row,
                {
                  justifyContent: fontScale > 1.3 ? "center" : "space-between",
                },
              ]}
            >
              {fontScale <= 1.3 && (
                <Text style={[styles.mono, { color: colors.muted }]}>
                  70 Hz
                </Text>
              )}
              <Text
                style={[
                  styles.mono,
                  { color: colors.muted, flexShrink: 1, textAlign: "center" },
                ]}
              >
                {audio.dominant < 0
                  ? "Tap a band to focus"
                  : `Peak · ${frequencyLabel(BAND_EDGES[audio.dominant])}–${frequencyLabel(BAND_EDGES[audio.dominant + 1])} Hz`}
              </Text>
              {fontScale <= 1.3 && (
                <Text style={[styles.mono, { color: colors.muted }]}>
                  9 kHz
                </Text>
              )}
            </View>
          </View>
          <View style={{ flexDirection: "row", flexWrap: "wrap", gap: 8 }}>
            {clips.map((item) => (
              <Button
                key={item.id}
                title={item.id === "voice" ? "Voice" : item.title}
                selected={clip.id === item.id}
                onPress={() => choose(item)}
              />
            ))}
            <Button
              title="＋"
              label="Import audio"
              selected={clip.id === "import"}
              onPress={() => void importAudio()}
            />
          </View>
          <View style={{ gap: 12 }}>
            <View style={[styles.row, { flexWrap: "wrap", gap: 8 }]}>
              <Text
                numberOfLines={1}
                style={{
                  color: colors.muted,
                  fontSize: 12,
                  flexShrink: 1,
                  paddingRight: 12,
                }}
              >
                {clip.id === "import" ? clip.title : clip.detail}
              </Text>
              <Text style={[styles.mono, { color: colors.muted }]}>
                {audio.duration > 0
                  ? `${clock(audio.position)} / ${clock(audio.duration)}`
                  : "LOCAL AUDIO"}
              </Text>
            </View>
            <View
              accessible={false}
              style={{
                height: 2,
                borderRadius: 1,
                backgroundColor: colors.line,
                overflow: "hidden",
              }}
            >
              <View
                style={{
                  height: 2,
                  backgroundColor: colors.signal,
                  width: `${audio.duration > 0 ? (audio.position / audio.duration) * 100 : 0}%`,
                }}
              />
            </View>
            <View style={{ flexDirection: "row", gap: 12 }}>
              <Pressable
                accessibilityRole="button"
                accessibilityLabel={
                  playing
                    ? "Pause audio"
                    : audio.status === "paused"
                      ? "Resume audio"
                      : "Play audio"
                }
                disabled={audio.status === "loading"}
                onPress={() => {
                  if (playing) void audio.pause();
                  else void audio.play(clip);
                }}
                style={({ pressed }) => [
                  styles.play,
                  {
                    flex: 1,
                    backgroundColor: colors.action,
                    borderWidth: StyleSheet.hairlineWidth,
                    borderColor: "#FFE9B2",
                    boxShadow:
                      mode === "dark"
                        ? "0 4px 20px #FFD07116"
                        : "0 4px 16px #9A671015",
                    opacity: pressed ? 0.85 : 1,
                  },
                ]}
              >
                <Text
                  style={{
                    color: colors.onAction,
                    fontSize: 16,
                    fontWeight: "600",
                  }}
                >
                  {playing
                    ? "Pause"
                    : audio.status === "loading"
                      ? "Loading…"
                      : audio.status === "paused"
                        ? "Resume"
                        : "Play audio"}
                </Text>
              </Pressable>
              <Button
                title="Stop"
                onPress={audio.stop}
                disabled={audio.status === "idle"}
              />
            </View>
            {!!audio.error && (
              <Text accessibilityRole="alert" style={{ color: colors.ink }}>
                {audio.error}
              </Text>
            )}
          </View>
          <View
            style={{
              borderTopWidth: StyleSheet.hairlineWidth,
              borderColor: colors.line,
              paddingTop: 8,
            }}
          >
            <Pressable
              accessibilityRole="button"
              accessibilityState={{ expanded: tuning }}
              onPress={() => setTuning((v) => !v)}
              style={[styles.row, { minHeight: 48 }]}
            >
              <Text
                style={{ color: colors.ink, fontSize: 15, fontWeight: "500" }}
              >
                Motion & tuning
              </Text>
              <Text style={{ color: colors.muted }}>{tuning ? "−" : "+"}</Text>
            </Pressable>
            {tuning && (
              <View style={{ gap: 16, paddingTop: 12 }}>
                <View style={styles.row}>
                  <Text style={{ color: colors.ink }}>Loop audio</Text>
                  <Switch
                    accessibilityLabel="Loop audio"
                    value={audio.loop}
                    onValueChange={audio.setLoop}
                    trackColor={{ true: colors.live }}
                  />
                </View>
                <Dial
                  label="Speaker volume"
                  value={volume}
                  min={0}
                  max={1}
                  format={(v) => `${Math.round(v * 100)}%`}
                  onChange={(v) => {
                    setVolume(v);
                    audio.setVolume(v);
                  }}
                />
                <Dial
                  label="Sensitivity"
                  value={sensitivity}
                  min={0.5}
                  max={2}
                  format={(v) => `${v.toFixed(2)}×`}
                  onChange={(v) => {
                    setSensitivity(v);
                    audio.setSensitivity(v);
                  }}
                />
                <Dial
                  label="Contour response"
                  value={movement}
                  min={0}
                  max={1.6}
                  format={(v) => `${v.toFixed(2)}×`}
                  onChange={(v) => {
                    setMovement(v);
                    motion.amount.set(v);
                  }}
                />
                <Dial
                  label="Attack"
                  value={attack}
                  min={15}
                  max={120}
                  format={(v) => `${Math.round(v)} ms`}
                  onChange={(v) => {
                    setAttack(v);
                    motion.attack.set(v);
                  }}
                />
                <Dial
                  label="Release"
                  value={release}
                  min={80}
                  max={600}
                  format={(v) => `${Math.round(v)} ms`}
                  onChange={(v) => {
                    setRelease(v);
                    motion.release.set(v);
                  }}
                />
                <View style={styles.row}>
                  <Text style={{ color: colors.ink }}>Reduce motion</Text>
                  <Switch
                    accessibilityLabel="Reduce motion"
                    value={motion.reduceMotion}
                    disabled={motion.systemReduced}
                    onValueChange={motion.setReduceOverride}
                    trackColor={{ true: colors.action }}
                  />
                </View>
                <Text
                  style={{ color: colors.muted, fontSize: 12, lineHeight: 18 }}
                >
                  Geometry freezes; audio and meters stay live. System Reduce
                  Motion always takes priority.
                </Text>
              </View>
            )}
          </View>
          <Text
            selectable
            style={[
              styles.mono,
              { color: colors.muted, textAlign: "center", lineHeight: 18 },
            ]}
          >
            {motion.metrics.fps} UI callbacks/s · p95 {motion.metrics.p95} ms
            {"\n"}Native FFT 4096 · {audio.sampleRate / 1000} kHz · local
            playback
          </Text>
        </View>
      </ScrollView>
    </>
  );
}
const styles = StyleSheet.create({
  button: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    minHeight: 44,
    borderRadius: 12,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: "center",
    justifyContent: "center",
  },
  play: {
    minHeight: 52,
    borderRadius: 12,
    alignItems: "center",
    justifyContent: "center",
  },
  row: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
  },
  mono: { fontFamily: "Menlo", fontSize: 10, fontVariant: ["tabular-nums"] },
});
