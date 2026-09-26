import React from "react";
import { Pressable, Text, View, useWindowDimensions } from "react-native";
import Animated, {
  useAnimatedStyle,
  interpolateColor,
  withTiming,
  type SharedValue,
} from "react-native-reanimated";
import { BAND_EDGES, frequencyLabel } from "./spectrum";
import { useLabTheme } from "./theme";

function Band({
  index,
  levels,
  selected,
  onSelect,
}: {
  index: number;
  levels: SharedValue<number[]>;
  selected: number;
  onSelect: (i: number) => void;
}) {
  const { colors } = useLabTheme();
  const { fontScale } = useWindowDimensions();
  const style = useAnimatedStyle(() => ({
    height: withTiming(3 + (levels.value[index] || 0) * 29, { duration: 80 }),
    backgroundColor: interpolateColor(
      levels.value[index] || 0,
      [0, 0.55],
      [colors.line, colors.signal],
    ),
  }));
  const label = `${frequencyLabel(BAND_EDGES[index])}–${frequencyLabel(BAND_EDGES[index + 1])} Hz`;
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={`Focus contour ${index + 1}, ${label}`}
      accessibilityState={{ selected: selected === index }}
      onPress={() => onSelect(selected === index ? -1 : index)}
      style={{
        flex: 1,
        minHeight: 52,
        justifyContent: "flex-end",
        alignItems: "center",
        gap: 4,
      }}
    >
      <View
        style={{
          height: 32,
          width: 6,
          justifyContent: "flex-end",
          backgroundColor: colors.surface,
          borderRadius: 3,
        }}
      >
        <Animated.View
          style={[
            {
              borderRadius: 3,
              opacity: selected >= 0 && selected !== index ? 0.3 : 1,
            },
            style,
          ]}
        />
      </View>
      {fontScale <= 1.3 && (
        <Text
          style={{
            color: selected === index ? colors.accent : colors.muted,
            fontSize: 9,
            fontVariant: ["tabular-nums"],
          }}
        >
          {index + 1}
        </Text>
      )}
    </Pressable>
  );
}
export function SpectrumMeter({
  levels,
  selected,
  onSelect,
}: {
  levels: SharedValue<number[]>;
  selected: number;
  onSelect: (i: number) => void;
}) {
  return (
    <View style={{ flexDirection: "row", gap: 2 }}>
      {Array.from({ length: 12 }, (_, i) => (
        <Band
          key={i}
          index={i}
          levels={levels}
          selected={selected}
          onSelect={onSelect}
        />
      ))}
    </View>
  );
}
