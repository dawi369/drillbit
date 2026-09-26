import React from "react";
import { Linking, Pressable, ScrollView, Text, View } from "react-native";
import { useLabTheme } from "../../theme";

const sources = [
  [
    "React Native Skia",
    "GPU drawing · MIT",
    "Native vector contours with shared animation values.",
    "https://github.com/Shopify/react-native-skia",
  ],
  [
    "React Native Reanimated",
    "UI-thread motion · MIT",
    "Frame-rate-independent attack and release. React stays out of the animation loop.",
    "https://github.com/software-mansion/react-native-reanimated",
  ],
  [
    "React Native Audio API",
    "Playback + FFT · MIT",
    "Real frequency data from the audio you hear. Requires a native development build.",
    "https://github.com/software-mansion/react-native-audio-api",
  ],
  [
    "expo-thinking-orbs",
    "Live comparison · MIT",
    "An existing dotted agent with voice states and three-band response. Installed here as the OSS reference.",
    "https://github.com/mahdidavoodi7/expo-thinking-orbs",
  ],
  [
    "ElevenLabs UI Orb",
    "Web reference · MIT",
    "A useful visual reference; its web renderer is not a native drop-in.",
    "https://ui.elevenlabs.io/docs/components/orb",
  ],
];
export default function Research() {
  const { colors } = useLabTheme();
  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      style={{ backgroundColor: colors.bg }}
      contentContainerStyle={{ padding: 24, paddingBottom: 40, gap: 28 }}
    >
      <Text
        style={{
          color: colors.ink,
          fontSize: 28,
          fontWeight: "500",
          letterSpacing: -0.7,
        }}
      >
        A voice with a shape.
      </Text>
      <Text style={{ color: colors.muted, fontSize: 16, lineHeight: 24 }}>
        Twelve amber contours. Low frequencies move the inner lines; higher
        frequencies move the outer lines. One continuous phase keeps the form
        together.
      </Text>
      {sources.map(([title, detail, body, url]) => (
        <Pressable
          key={title}
          accessibilityRole="link"
          onPress={() => void Linking.openURL(url)}
          style={{
            gap: 8,
            borderTopWidth: 0.5,
            borderColor: colors.line,
            paddingTop: 20,
          }}
        >
          <Text style={{ color: colors.ink, fontSize: 19, fontWeight: "500" }}>
            {title} ↗
          </Text>
          <Text style={{ color: colors.muted, fontSize: 12 }}>{detail}</Text>
          <Text style={{ color: colors.muted, fontSize: 15, lineHeight: 22 }}>
            {body}
          </Text>
        </Pressable>
      ))}
      <View style={{ gap: 12 }}>
        <Text style={{ color: colors.ink, fontSize: 19, fontWeight: "500" }}>
          What this proves
        </Text>
        <Text style={{ color: colors.muted, fontSize: 15, lineHeight: 23 }}>
          Native rendering, real FFT, and local playback. It does not connect to
          an AI agent, record your microphone, or prove performance on a
          physical device. The callback counter is a timing diagnostic, not a
          GPU benchmark.
        </Text>
        <Text style={{ color: colors.muted, fontSize: 15, lineHeight: 23 }}>
          The interviewer sample is an original prompt rendered with macOS
          Samantha. Band scan and sweep are generated locally. Imported files
          stay on this device; playback stops when you leave the lab.
        </Text>
      </View>
    </ScrollView>
  );
}
