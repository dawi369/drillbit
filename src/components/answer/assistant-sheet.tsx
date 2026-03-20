import { BottomSheet, Button, Input, Label, TextField } from "heroui-native";
import { BottomSheetScrollView } from "@gorhom/bottom-sheet";
import { useReanimatedKeyboardAnimation } from "react-native-keyboard-controller";
import { Text, View, useWindowDimensions } from "react-native";
import Animated, {
  Extrapolation,
  interpolate,
  useAnimatedStyle,
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

function EmbeddedSection({ children }: { children: React.ReactNode }) {
  return <View className="rounded-[24px] bg-surface-secondary/10 px-2 py-2">{children}</View>;
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
  const { height, progress } = useReanimatedKeyboardAnimation();
  const { height: windowHeight } = useWindowDimensions();

  const liftedContentStyle = useAnimatedStyle(() => {
    const keyboardHeight = Math.abs(height.value);
    const maxLift = windowHeight * 0.28;
    const liftDistance = Math.min(keyboardHeight, maxLift);
    const translateY = interpolate(
      progress.value,
      [0, 1],
      [0, -liftDistance],
      Extrapolation.CLAMP,
    );

    return {
      transform: [
        {
          translateY,
        },
      ],
    };
  }, [height, progress, windowHeight]);

  return (
    <BottomSheet isOpen={visible} onOpenChange={(isOpen) => !isOpen && onClose()}>
      <BottomSheet.Portal>
        <BottomSheet.Overlay className="bg-black/18" />
        <BottomSheet.Content
          index={0}
          snapPoints={["86%"]}
          enableDynamicSizing={false}
          keyboardBehavior="interactive"
          keyboardBlurBehavior="restore"
          android_keyboardInputMode="adjustResize"
        >
          <Animated.View
            className="gap-5 rounded-t-[32px] border border-border/45 bg-background px-5 pb-safe-offset-5 pt-4"
            style={liftedContentStyle}
          >
            <View className="gap-1">
              <BottomSheet.Title className="text-xl font-semibold tracking-tight text-foreground">
                {title}
              </BottomSheet.Title>
              <BottomSheet.Description className="text-sm leading-6 text-muted">
                {description}
              </BottomSheet.Description>
            </View>

            <EmbeddedSection>
              <BottomSheetScrollView
                className="max-h-[360px]"
                contentContainerClassName="gap-3 px-4 py-4"
                showsVerticalScrollIndicator={false}
              >
                {assistantHistory.length > 0 ? (
                  assistantHistory.map((message) => (
                    <MessageBubble key={message.id} role={message.role} text={message.text} />
                  ))
                ) : (
                  <View className="rounded-[20px] border border-dashed border-border/40 bg-background/70 px-4 py-4">
                    <Text className="text-sm leading-6 text-muted">
                      {mode === "reveal"
                        ? "Ask for alternatives, better phrasing, or a clearer final answer shape."
                        : "Ask for the next hint, pressure test your approach, or request a more direct nudge."}
                    </Text>
                  </View>
                )}
              </BottomSheetScrollView>
            </EmbeddedSection>

            <EmbeddedSection>
              <TextField>
                <Label>clarifying question</Label>
                <Input
                  multiline
                  numberOfLines={8}
                  placeholder="Ask a clarifying question about what you are working on..."
                  value={assistantMessage}
                  onChangeText={onChangeMessage}
                  className="max-h-[220px] min-h-44 items-start py-4"
                  textAlignVertical="top"
                  scrollEnabled
                  isDisabled={!canInteractWithChallenge}
                />
              </TextField>
            </EmbeddedSection>

            <View className="flex-row gap-3">
              <Button className="flex-1" variant="secondary" onPress={onClose}>
                <Button.Label>close</Button.Label>
              </Button>
              <Button
                className="flex-1"
                variant="primary"
                onPress={onSubmit}
                isDisabled={!canInteractWithChallenge}
              >
                <Button.Label>{isAssistantLoading ? "thinking..." : "send"}</Button.Label>
              </Button>
            </View>
          </Animated.View>
        </BottomSheet.Content>
      </BottomSheet.Portal>
    </BottomSheet>
  );
}
