import { useEffect } from "react";
import { Pressable, Text, View } from "react-native";
import Animated, {
  Easing,
  useAnimatedStyle,
  useSharedValue,
  withRepeat,
  withSequence,
  withTiming,
} from "react-native-reanimated";

import { cn } from "@/lib/cn";
import type { ChallengeMode } from "@/lib/widgets/types";

export type AssistantFieldStatus =
  | "idle"
  | "thinking"
  | "streaming"
  | "done"
  | "error";

function getAssistantStatusLabel(status?: AssistantFieldStatus) {
  if (!status || status === "idle") {
    return null;
  }

  if (status === "thinking") {
    return "thinking...";
  }

  if (status === "streaming") {
    return "streaming...";
  }

  if (status === "error") {
    return "error";
  }

  return "ready";
}

function getAssistantFallbackCopy(
  mode: Extract<ChallengeMode, "coach" | "reveal">,
  status?: AssistantFieldStatus,
) {
  if (status === "thinking") {
    return mode === "coach"
      ? "coach is reviewing your notes and looking for the next pressure point."
      : "reveal is assembling a stronger end-to-end answer before it streams in.";
  }

  if (status === "streaming") {
    return mode === "coach"
      ? "coach is streaming the next hint into place."
      : "reveal is streaming the full answer structure into place.";
  }

  return mode === "coach"
    ? "coach will activate once you have types enough to show your direction"
    : "reveal will give one structured answer surface here — tap to inspect and ask follow-ups later";
}

export function AssistantHeader({
  mode,
  guidance,
  latestMessage,
  status,
  onPress,
}: {
  mode: ChallengeMode;
  guidance?: string | null;
  latestMessage?: string | null;
  status?: AssistantFieldStatus;
  onPress: () => void;
}) {
  const dotPhase = useSharedValue(0.55);

  useEffect(() => {
    if (status === "thinking" || status === "streaming") {
      dotPhase.value = withRepeat(
        withSequence(
          withTiming(1, { duration: 520, easing: Easing.inOut(Easing.ease) }),
          withTiming(0.4, { duration: 520, easing: Easing.inOut(Easing.ease) }),
        ),
        -1,
        false,
      );
      return;
    }

    dotPhase.value = withTiming(0.55, {
      duration: 180,
      easing: Easing.out(Easing.ease),
    });
  }, [dotPhase, status]);

  const dotAStyle = useAnimatedStyle(() => ({
    opacity: dotPhase.value,
    transform: [{ scale: 0.92 + dotPhase.value * 0.08 }],
  }));
  const dotBStyle = useAnimatedStyle(() => ({
    opacity: Math.max(0.3, dotPhase.value - 0.12),
    transform: [{ scale: 0.92 + Math.max(0.3, dotPhase.value - 0.12) * 0.08 }],
  }));
  const dotCStyle = useAnimatedStyle(() => ({
    opacity: Math.max(0.22, dotPhase.value - 0.24),
    transform: [{ scale: 0.92 + Math.max(0.22, dotPhase.value - 0.24) * 0.08 }],
  }));

  if (mode === "solo") {
    return null;
  }

  const assistantMode = mode as Extract<ChallengeMode, "coach" | "reveal">;
  const statusLabel = getAssistantStatusLabel(status);

  return (
    <Pressable
      className={cn(
        "border-b border-border bg-surface-secondary px-5 py-3",
      )}
      onPress={onPress}
    >
      <Text className="mb-1 text-xs font-medium uppercase tracking-[1px] text-muted">
        {mode === "coach" ? "ai coach" : "reveal"}
      </Text>
      {statusLabel ? (
        <Text className="mb-1 text-xs font-medium uppercase tracking-[1px] text-muted">
          {statusLabel}
        </Text>
      ) : null}
      <Text className="text-sm leading-6 text-foreground">
        {guidance ?? latestMessage ?? getAssistantFallbackCopy(assistantMode, status)}
      </Text>
      {status === "thinking" || status === "streaming" ? (
        <View className="mt-2 flex-row items-center gap-1">
          <Animated.View className="h-1.5 w-1.5 rounded-full bg-muted" style={dotAStyle} />
          <Animated.View className="h-1.5 w-1.5 rounded-full bg-muted" style={dotBStyle} />
          <Animated.View className="h-1.5 w-1.5 rounded-full bg-muted" style={dotCStyle} />
        </View>
      ) : null}
    </Pressable>
  );
}
