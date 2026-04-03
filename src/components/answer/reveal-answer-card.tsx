import { Text } from "react-native";
import Animated, { Easing, useAnimatedStyle, withTiming } from "react-native-reanimated";

export function RevealAnswerCard({
  answer,
  visible,
}: {
  answer: string;
  visible: boolean;
}) {
  const animatedStyle = useAnimatedStyle(
    () => ({
      opacity: withTiming(visible ? 1 : 0, {
        duration: 220,
        easing: Easing.out(Easing.cubic),
      }),
      transform: [
        {
          translateY: withTiming(visible ? 0 : 8, {
            duration: 220,
            easing: Easing.out(Easing.cubic),
          }),
        },
      ],
    }),
    [visible],
  );

  return (
    <Animated.View
      className="rounded-[var(--radius)] border border-border bg-surface-secondary px-4 py-4"
      style={animatedStyle}
    >
      <Text className="mb-2 text-xs font-medium uppercase tracking-[1px] text-muted">
        reveal answer
      </Text>
      <Text selectable className="text-sm leading-6 text-foreground">
        {answer}
      </Text>
    </Animated.View>
  );
}
