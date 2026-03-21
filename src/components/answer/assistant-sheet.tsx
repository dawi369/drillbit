import { BottomSheet, Button } from "heroui-native";
import {
  BottomSheetScrollView,
  BottomSheetTextInput,
  BottomSheetView,
  type BottomSheetScrollViewMethods,
} from "@gorhom/bottom-sheet";
import { useCallback, useEffect, useRef } from "react";
import {
  Keyboard,
  type NativeScrollEvent,
  type NativeSyntheticEvent,
  Platform,
  Text,
  View,
  useColorScheme,
  useWindowDimensions,
} from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import Animated, {
  Easing,
  useAnimatedStyle,
  useSharedValue,
  withDelay,
  withRepeat,
  withSequence,
  withTiming,
} from "react-native-reanimated";

import type { AssistantChatMessage, AssistantChatRole } from "@/components/answer/assistant-history";
import { cn } from "@/lib/cn";
import type { ChallengeMode } from "@/lib/widgets/types";

function MessageBubble({
  role,
  text,
  isStreaming = false,
}: {
  role: AssistantChatRole;
  text: string;
  isStreaming?: boolean;
}) {
  return (
    <View className={cn("w-full", role === "you" ? "items-end" : "items-start")}>
      <View
        className={cn(
          "max-w-[85%] rounded-[24px] border px-4 py-3",
          role === "you"
            ? "border-border bg-surface-secondary"
            : role === "coach"
            ? "border-accent/20 bg-accent/10"
            : "border-border/50 bg-surface-secondary/10",
        )}
      >
        <Text className="mb-1 text-[10px] font-medium uppercase tracking-[1.2px] text-muted">
          {role}
        </Text>
        {text.trim().length > 0 ? (
          <Text className="text-sm leading-6 text-foreground">{text}</Text>
        ) : isStreaming ? (
          <View className="h-[22px] flex-row items-center gap-1">
            <StreamingDot delay={0} />
            <StreamingDot delay={120} />
            <StreamingDot delay={240} />
          </View>
        ) : null}
        {isStreaming && text.trim().length > 0 ? (
          <View className="mt-2 flex-row items-center gap-1">
            <StreamingDot delay={0} />
            <StreamingDot delay={120} />
            <StreamingDot delay={240} />
          </View>
        ) : null}
      </View>
    </View>
  );
}

function StreamingDot({ delay }: { delay: number }) {
  const phase = useSharedValue(0.28);

  useEffect(() => {
    phase.value = withDelay(
      delay,
      withRepeat(
        withSequence(
          withTiming(1, { duration: 420, easing: Easing.inOut(Easing.ease) }),
          withTiming(0.28, { duration: 420, easing: Easing.inOut(Easing.ease) }),
        ),
        -1,
        false,
      ),
    );
  }, [delay, phase]);

  const animatedStyle = useAnimatedStyle(() => ({
    opacity: phase.value,
    transform: [{ scale: 0.92 + phase.value * 0.12 }],
  }));

  return (
    <Animated.View className="h-1.5 w-1.5 rounded-full bg-muted" style={animatedStyle} />
  );
}

export function AssistantSheet({
  visible,
  mode,
  assistantHistory,
  assistantMessage,
  isAssistantLoading,
  canInteractWithChallenge,
  onClose,
  onChangeMessage,
  onSubmit,
}: {
  visible: boolean;
  mode: ChallengeMode;
  assistantHistory: AssistantChatMessage[];
  assistantMessage: string;
  isAssistantLoading: boolean;
  canInteractWithChallenge: boolean;
  onClose: () => void;
  onChangeMessage: (value: string) => void;
  onSubmit: () => void;
}) {
  const title = mode === "reveal" ? "ask about the reveal" : "ask the coach";
  const description =
    mode === "reveal"
      ? "Follow the full answer, inspect trade-offs, and ask for sharper revisions."
      : "Keep a lightweight coaching thread with your latest hint and follow-up questions.";
  const historyScrollRef = useRef<BottomSheetScrollViewMethods | null>(null);
  const insets = useSafeAreaInsets();
  const colorScheme = useColorScheme();
  const isDark = colorScheme === "dark";
  const { height: windowHeight } = useWindowDimensions();
  const canSend = canInteractWithChallenge && assistantMessage.trim().length > 0 && !isAssistantLoading;
  const keyboardLift = useSharedValue(0);
  const shouldStickToBottomRef = useRef(true);
  const lastHistoryEntryRef = useRef<string | null>(null);
  const scrollTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const isSheetVisibleRef = useRef(visible);
  const historyCardHeight = Math.min(Math.max(windowHeight * 0.36, 220), 340);

  const scheduleScrollToEnd = useCallback((animated: boolean) => {
    if (!isSheetVisibleRef.current) {
      return;
    }

    if (scrollTimeoutRef.current) {
      clearTimeout(scrollTimeoutRef.current);
    }

    scrollTimeoutRef.current = setTimeout(() => {
      if (!isSheetVisibleRef.current) {
        scrollTimeoutRef.current = null;
        return;
      }

      historyScrollRef.current?.scrollToEnd({ animated });
      scrollTimeoutRef.current = null;
    }, 40);
  }, []);

  const handleHistoryScroll = useCallback(
    (event: NativeSyntheticEvent<NativeScrollEvent>) => {
      const { contentOffset, contentSize, layoutMeasurement } = event.nativeEvent;
      const distanceFromBottom =
        contentSize.height - (contentOffset.y + layoutMeasurement.height);

      shouldStickToBottomRef.current = distanceFromBottom <= 48;
    },
    [],
  );

  useEffect(() => {
    isSheetVisibleRef.current = visible;

    if (!visible && scrollTimeoutRef.current) {
      clearTimeout(scrollTimeoutRef.current);
      scrollTimeoutRef.current = null;
      Keyboard.dismiss();
      keyboardLift.value = 0;
    }
  }, [visible]);

  useEffect(() => {
    return () => {
      if (scrollTimeoutRef.current) {
        clearTimeout(scrollTimeoutRef.current);
      }
    };
  }, []);

  useEffect(() => {
    if (!visible) {
      return;
    }

    shouldStickToBottomRef.current = true;
    scheduleScrollToEnd(false);
  }, [scheduleScrollToEnd, visible]);

  useEffect(() => {
    if (!visible || assistantHistory.length === 0) {
      lastHistoryEntryRef.current = null;
      return;
    }

    const lastEntry = assistantHistory[assistantHistory.length - 1];
    const previousLastEntryId = lastHistoryEntryRef.current;
    const appendedNewEntry = lastEntry?.id !== previousLastEntryId;

    lastHistoryEntryRef.current = lastEntry?.id ?? null;

    if (!shouldStickToBottomRef.current) {
      return;
    }

    scheduleScrollToEnd(appendedNewEntry);
  }, [assistantHistory, scheduleScrollToEnd, visible]);

  useEffect(() => {
    const showEvent = Platform.OS === "ios" ? "keyboardWillShow" : "keyboardDidShow";
    const hideEvent = Platform.OS === "ios" ? "keyboardWillHide" : "keyboardDidHide";

    const showSubscription = Keyboard.addListener(showEvent, (event) => {
      const lift = Math.min(event.endCoordinates.height * 0.72, windowHeight * 0.34);
      keyboardLift.value = withTiming(lift, {
        duration: 280,
        easing: Easing.out(Easing.cubic),
      });
    });

    const hideSubscription = Keyboard.addListener(hideEvent, () => {
      keyboardLift.value = withTiming(0, {
        duration: 240,
        easing: Easing.out(Easing.cubic),
      });
    });

    return () => {
      showSubscription.remove();
      hideSubscription.remove();
    };
  }, [keyboardLift, windowHeight]);

  const contentLiftStyle = useAnimatedStyle(() => ({
    transform: [{ translateY: -keyboardLift.value }],
  }));

  return (
    <BottomSheet isOpen={visible} onOpenChange={(isOpen) => !isOpen && onClose()}>
      <BottomSheet.Portal>
        <BottomSheet.Overlay className="bg-black/18" />
        <BottomSheet.Content
          index={0}
          snapPoints={["86%"]}
          enableDynamicSizing={false}
          keyboardBehavior="extend"
          keyboardBlurBehavior="none"
          android_keyboardInputMode="adjustPan"
          enableContentPanningGesture={false}
          backgroundClassName="rounded-t-[32px] bg-background"
          contentContainerClassName="pt-3"
        >
          <BottomSheetView
            className="flex-1"
            style={{
              minHeight: 0,
              paddingHorizontal: 20,
              paddingBottom: Math.max(insets.bottom, 12) + 12,
            }}
          >
            <Animated.View className="flex-1 gap-4" style={contentLiftStyle}>
              <View className="gap-1 px-1">
                <Text className="text-xl font-semibold tracking-tight text-foreground">
                  {title}
                </Text>
                <Text className="text-sm leading-6 text-muted">{description}</Text>
              </View>

              <View className="flex-1 justify-between gap-4">
                <View
                  className="overflow-hidden rounded-[28px] border border-border/40 bg-surface-secondary/10"
                  style={{ height: historyCardHeight }}
                >
                  <View className="flex-1 overflow-hidden px-3 py-3" style={{ minHeight: 0 }}>
                    <BottomSheetScrollView
                      ref={historyScrollRef}
                      style={{ flex: 1, minHeight: 0 }}
                      onScroll={handleHistoryScroll}
                      scrollEventThrottle={16}
                      contentContainerStyle={{
                        gap: 12,
                        paddingHorizontal: 4,
                        paddingBottom: 8,
                      }}
                      showsVerticalScrollIndicator
                      keyboardShouldPersistTaps="handled"
                    >
                      {assistantHistory.length > 0 ? (
                        assistantHistory.map((message) => (
                          <MessageBubble
                            key={message.id}
                            role={message.role}
                            text={message.text}
                            isStreaming={message.isStreaming}
                          />
                        ))
                      ) : (
                        <View className="rounded-[20px] bg-background px-4 py-4">
                          <Text className="text-sm leading-6 text-muted">
                            {mode === "reveal"
                              ? "Ask for alternatives, better phrasing, or a clearer final answer shape."
                              : "Ask for the next hint, pressure test your approach, or request a more direct nudge."}
                          </Text>
                        </View>
                      )}
                    </BottomSheetScrollView>
                  </View>
                </View>

                <View>
                  <View
                    className="rounded-[28px] border border-border/40 bg-surface-secondary/10 px-3 py-3"
                    style={{ marginBottom: 3 }}
                  >
                    <BottomSheetTextInput
                      multiline
                      numberOfLines={5}
                      placeholder="Ask a follow-up..."
                      placeholderTextColor={isDark ? "rgba(226,232,240,0.48)" : "rgba(15,23,42,0.42)"}
                      value={assistantMessage}
                      onChangeText={onChangeMessage}
                      style={{
                        minHeight: 104,
                        maxHeight: 176,
                        color: isDark ? "#f8fafc" : "#0f172a",
                        paddingHorizontal: 12,
                        paddingTop: 10,
                        paddingBottom: 48,
                        paddingRight: 88,
                        fontSize: 16,
                        lineHeight: 22,
                        textAlignVertical: "top",
                      }}
                      scrollEnabled
                      editable={canInteractWithChallenge}
                    />

                    <View className="absolute bottom-3 right-3">
                      <Button
                        size="sm"
                        variant="primary"
                        onPress={onSubmit}
                        isDisabled={!canSend}
                      >
                        <Button.Label>{isAssistantLoading ? "wait" : "send"}</Button.Label>
                      </Button>
                    </View>
                  </View>
                </View>
              </View>
            </Animated.View>
          </BottomSheetView>
        </BottomSheet.Content>
      </BottomSheet.Portal>
    </BottomSheet>
  );
}
