import { BottomSheet, Button } from "heroui-native";
import {
  BottomSheetScrollView,
  BottomSheetTextInput,
  BottomSheetView,
  type BottomSheetScrollViewMethods,
} from "@gorhom/bottom-sheet";
import { useEffect, useRef } from "react";
import {
  Keyboard,
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
  withTiming,
} from "react-native-reanimated";

import { cn } from "@/lib/cn";
import type { ChallengeMode } from "@/lib/widgets/types";

function MessageBubble({
  role,
  text,
}: {
  role: "coach" | "you";
  text: string;
}) {
  return (
    <View className={cn("w-full", role === "coach" ? "items-start" : "items-end")}>
      <View
        className={cn(
          "max-w-[85%] rounded-[24px] border px-4 py-3",
          role === "coach"
            ? "border-accent/20 bg-accent/10"
            : "border-border bg-surface-secondary",
        )}
      >
        <Text className="mb-1 text-[10px] font-medium uppercase tracking-[1.2px] text-muted">
          {role}
        </Text>
        <Text className="text-sm leading-6 text-foreground">{text}</Text>
      </View>
    </View>
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
  assistantHistory: { id: string; role: "coach" | "you"; text: string }[];
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

  useEffect(() => {
    const timeout = setTimeout(() => {
      historyScrollRef.current?.scrollToEnd({ animated: true });
    }, 40);

    return () => clearTimeout(timeout);
  }, [assistantHistory]);

  useEffect(() => {
    const showEvent = Platform.OS === "ios" ? "keyboardWillShow" : "keyboardDidShow";
    const hideEvent = Platform.OS === "ios" ? "keyboardWillHide" : "keyboardDidHide";

    const showSubscription = Keyboard.addListener(showEvent, (event) => {
      const lift = Math.min(event.endCoordinates.height * 0.92, windowHeight * 0.42);
      keyboardLift.value = withTiming(lift, {
        duration: 280,
        easing: Easing.out(Easing.cubic),
      });
    });

    const hideSubscription = Keyboard.addListener(hideEvent, () => {
      keyboardLift.value = withTiming(0, {
        duration: 260,
        easing: Easing.out(Easing.cubic),
      });
    });

    return () => {
      showSubscription.remove();
      hideSubscription.remove();
    };
  }, [keyboardLift, windowHeight]);

  const liftedContentStyle = useAnimatedStyle(() => {
    return {
      transform: [
        {
          translateY: -keyboardLift.value,
        },
      ],
    };
  }, [keyboardLift]);

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
            <View className="gap-1 px-1">
              <Text className="text-xl font-semibold tracking-tight text-foreground">
                {title}
              </Text>
              <Text className="text-sm leading-6 text-muted">{description}</Text>
            </View>

            <View className="mt-4 flex-1 overflow-hidden">
              <Animated.View style={liftedContentStyle} className="flex-1">
                <BottomSheetScrollView
                  ref={historyScrollRef}
                  style={{ flex: 1, minHeight: 0 }}
                  contentContainerClassName="gap-3 px-1 pb-4"
                  showsVerticalScrollIndicator
                  keyboardShouldPersistTaps="handled"
                >
                  {assistantHistory.length > 0 ? (
                    assistantHistory.map((message) => (
                      <MessageBubble key={message.id} role={message.role} text={message.text} />
                    ))
                  ) : (
                    <View className="rounded-[20px] bg-surface-secondary/10 px-4 py-4">
                      <Text className="text-sm leading-6 text-muted">
                        {mode === "reveal"
                          ? "Ask for alternatives, better phrasing, or a clearer final answer shape."
                          : "Ask for the next hint, pressure test your approach, or request a more direct nudge."}
                      </Text>
                    </View>
                  )}
                </BottomSheetScrollView>

                <View
                  className="mt-3 rounded-[28px] border border-border/40 bg-surface-secondary/10 px-3 py-3"
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
              </Animated.View>
            </View>
          </BottomSheetView>
        </BottomSheet.Content>
      </BottomSheet.Portal>
    </BottomSheet>
  );
}
