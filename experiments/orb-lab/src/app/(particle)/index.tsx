import React, { useCallback, useEffect, useMemo, useState } from "react";
import {
  Alert,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
  useWindowDimensions,
} from "react-native";
import { router, useFocusEffect } from "expo-router";
import { StatusBar } from "expo-status-bar";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { Canvas, LinearGradient, Path, Rect, Skia, vec } from "@shopify/react-native-skia";
import { useAudio, clips, type Clip } from "../../use-audio";
import { useMotion } from "../../use-motion";
import { ParticleField } from "../../particle-field";
import { ParticleWaveform } from "../../particle-waveform";
import { particlePalette as color } from "../../particle-palette";

function makeStars(width: number, height: number) {
  const path = Skia.PathBuilder.Make();
  let seed = 0x9157234;
  const next = () => {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return seed / 4294967296;
  };
  const count = Math.round((width * height) / 1700);
  for (let i = 0; i < count; i++) {
    path.addCircle(next() * width, next() * height, 0.25 + next() * 0.42);
  }
  return path.build();
}

function Atmosphere({ width, height }: { width: number; height: number }) {
  const stars = useMemo(() => makeStars(width, height), [width, height]);
  return (
    <Canvas
      pointerEvents="none"
      style={StyleSheet.absoluteFill}
      accessible={false}
    >
      <Rect x={0} y={0} width={width} height={height}>
        <LinearGradient
          start={vec(0, 0)}
          end={vec(0, height)}
          colors={[color.top, color.upper, color.middle, color.bottom]}
          positions={[0, 0.28, 0.61, 1]}
        />
      </Rect>
      <Path path={stars} color={color.particle} opacity={0.32} />
    </Canvas>
  );
}

const clock = (n: number) =>
  `${Math.floor(n / 60)}:${String(Math.floor(n % 60)).padStart(2, "0")}`;

export default function ParticleConcept() {
  const { width, height, fontScale } = useWindowDimensions();
  const insets = useSafeAreaInsets();
  const [canvasHeight, setCanvasHeight] = useState(height);
  const [focused, setFocused] = useState(true);
  const [clip, setClip] = useState<Clip>(clips[0]);
  const audio = useAudio();
  const setLoop = audio.setLoop;
  const motion = useMotion(audio.targets, focused);
  const stop = audio.stop;
  const fieldSize = Math.min(width - 24, height * 0.51, 430);
  const playing = audio.status === "playing";
  const busy = audio.status === "loading";

  useEffect(() => setLoop(false), [setLoop]);
  useFocusEffect(
    useCallback(() => {
      setFocused(true);
      return () => {
        setFocused(false);
        stop();
      };
    }, [stop]),
  );

  const chooseSource = () => {
    Alert.alert(
      "Test audio",
      "Choose the signal that moves the particles.",
      [
        ...clips.map((item) => ({
          text: item.id === "voice" ? "Voice" : item.title,
          onPress: () => {
            audio.stop();
            setClip(item);
          },
        })),
        { text: "Cancel", style: "cancel" as const },
      ],
    );
  };

  const pressTransport = () => {
    if (playing) audio.stop();
    else void audio.play(clip);
  };

  return (
    <>
      <StatusBar style="light" />
      <ScrollView
        key={`scale-${fontScale}`}
        contentInsetAdjustmentBehavior="never"
        bounces={false}
        style={{ flex: 1, backgroundColor: color.bottom }}
        contentContainerStyle={{
          flexGrow: 1,
          minHeight: Math.max(570, height - 80),
        }}
      >
        <View
          onLayout={(event) => setCanvasHeight(event.nativeEvent.layout.height)}
          style={{ flex: 1, minHeight: Math.max(570, height - 80) }}
        >
          <Atmosphere width={width} height={canvasHeight} />
          <View
            style={{
              paddingTop: insets.top + 18,
              paddingHorizontal: 24,
              flexDirection: "row",
              justifyContent: "space-between",
              alignItems: "center",
            }}
          >
            <Pressable
              accessibilityRole="button"
              accessibilityLabel="Close particle concept"
              onPress={() => router.navigate("/(lab)")}
              style={({ pressed }) => [styles.roundControl, { opacity: pressed ? 0.72 : 1 }]}
            >
              <View
                style={{
                  width: 22,
                  height: 22,
                  alignItems: "center",
                  justifyContent: "center",
                }}
              >
                <View
                  style={{
                    position: "absolute",
                    width: 22,
                    height: 2,
                    backgroundColor: color.white,
                    transform: [{ rotate: "45deg" }],
                  }}
                />
                <View
                  style={{
                    position: "absolute",
                    width: 22,
                    height: 2,
                    backgroundColor: color.white,
                    transform: [{ rotate: "-45deg" }],
                  }}
                />
              </View>
            </Pressable>
            <Pressable
              accessibilityRole="button"
              accessibilityLabel={`Test source: ${clip.title}. Change source`}
              onPress={chooseSource}
              style={{ minHeight: 44, justifyContent: "center", paddingHorizontal: 8 }}
            >
              <Text
                style={{
                  color: color.label,
                  fontSize: 11,
                  fontWeight: "600",
                  letterSpacing: 1.7,
                }}
              >
                {clip.id === "voice" ? "VOICE" : clip.title.toUpperCase()}  ⌄
              </Text>
            </Pressable>
          </View>

          <View
            style={{
              flex: 1,
              minHeight: fieldSize,
              alignItems: "center",
              justifyContent: "center",
            }}
            accessible
            accessibilityLabel={`Particle agent. ${playing ? (clip.id === "voice" ? "Responding to voice" : "Responding to test audio") : "Ready"}. ${motion.reduceMotion ? "Reduced motion enabled" : ""}`}
          >
            <ParticleField size={fieldSize} motion={motion.motion} />
          </View>

          <View
            style={{
              alignItems: "center",
              gap: 12,
              paddingHorizontal: 24,
              paddingBottom: Math.max(insets.bottom, 16) + 102,
            }}
          >
            <View
              accessible
              accessibilityLabel="Voice waveform"
              style={{ minHeight: 40, justifyContent: "center" }}
            >
              <ParticleWaveform motion={motion.motion} />
            </View>
            <Text
              selectable
              accessibilityLiveRegion="polite"
              style={{
                color: color.label,
                fontSize: 16,
                fontVariant: ["tabular-nums"],
                letterSpacing: 0.2,
              }}
            >
              {clock(audio.position)}
            </Text>
            <Pressable
              accessibilityRole="button"
              accessibilityLabel={
                playing
                  ? "Stop audio"
                  : `Play ${clip.id === "voice" ? "voice" : clip.title.toLowerCase()} audio`
              }
              accessibilityState={{ disabled: busy }}
              disabled={busy}
              onPress={pressTransport}
              style={({ pressed }) => [
                styles.transport,
                { opacity: busy ? 0.5 : pressed ? 0.76 : 1 },
              ]}
            >
              <View
                style={
                  playing
                    ? { width: 22, height: 22, borderRadius: 5, backgroundColor: color.coral }
                    : {
                        width: 0,
                        height: 0,
                        marginLeft: 5,
                        borderTopWidth: 13,
                        borderBottomWidth: 13,
                        borderLeftWidth: 22,
                        borderTopColor: "transparent",
                        borderBottomColor: "transparent",
                        borderLeftColor: color.coral,
                      }
                }
              />
            </Pressable>
            {!!audio.error && (
              <Text accessibilityRole="alert" style={{ color: color.white, textAlign: "center" }}>
                {audio.error}
              </Text>
            )}
          </View>
        </View>
      </ScrollView>
    </>
  );
}

const styles = StyleSheet.create({
  roundControl: {
    width: 48,
    height: 48,
    borderRadius: 24,
    alignItems: "center",
    justifyContent: "center",
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: "#666666",
    backgroundColor: "#4A4A4A",
  },
  transport: {
    width: 72,
    height: 72,
    borderRadius: 36,
    alignItems: "center",
    justifyContent: "center",
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: color.controlLine,
    backgroundColor: color.control,
  },
});
