import { useLocalSearchParams } from "expo-router";
import { Input, Label, TextField } from "heroui-native";
import { useEffect, useState } from "react";
import { Keyboard, Pressable, ScrollView, Text, View } from "react-native";
import Animated, {
  Easing,
  useAnimatedStyle,
  useSharedValue,
  withTiming,
} from "react-native-reanimated";
import { KeyboardAwareScrollView } from "react-native-keyboard-controller";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { AssistantHeader } from "@/components/answer/assistant-header";
import { HeaderMenuButton } from "@/components/answer/header-menu-button";
import { RevealAnswerCard } from "@/components/answer/reveal-answer-card";
import { AssistantSheet } from "@/components/answer/assistant-sheet";
import { useAnswerController } from "@/components/answer/use-answer-controller";
import { cn } from "@/lib/cn";
import { debugLog } from "@/lib/debug";

function HeaderToggle({
  collapsed,
  onPress,
}: {
  collapsed: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable className="items-center px-3 py-1" onPress={onPress}>
      <View className="items-center gap-1">
        <View className="h-4 w-16 items-center justify-center">
          <View className="relative h-3 w-12">
            <View
              className={cn(
                "absolute left-1 top-1 h-0.5 w-5 rounded-full bg-border",
                collapsed ? "rotate-12" : "-rotate-12",
              )}
            />
            <View
              className={cn(
                "absolute right-1 top-1 h-0.5 w-5 rounded-full bg-border",
                collapsed ? "-rotate-12" : "rotate-12",
              )}
            />
          </View>
        </View>
      </View>
    </Pressable>
  );
}

export function AnswerScreen() {
  const insets = useSafeAreaInsets();
  const params = useLocalSearchParams<{
    mode?: string;
    challengeId?: string;
  }>();
  const resolvedRouteMode = params.mode === "solo" || params.mode === "coach" || params.mode === "reveal"
    ? params.mode
    : null;
  const resolvedChallengeId = params.challengeId ?? null;
  const [isHeaderCollapsed, setHeaderCollapsed] = useState(false);
  const [isAssistantInputOpen, setAssistantInputOpen] = useState(false);
  const [isHeaderTeaserOverflowing, setHeaderTeaserOverflowing] = useState(false);
  const headerProgress = useSharedValue(isHeaderCollapsed ? 0 : 1);

  const {
    assistantGuidance,
    assistantHistory,
    assistantMessage,
    assistantStatus,
    availableModels,
    canInteractWithChallenge,
    challenge,
    handleAssistantSubmit,
    handleDone,
    handleSave,
    handleSelectModel,
    handleSkip,
    isAssistantLoading,
    isChallengeLoading,
    latestAssistantMessage,
    notesDraft,
    revealAnswer,
    selectedMode,
    selectedModelId,
    setAssistantDraft,
    setAssistantMessage,
    setNotesDraft,
    setSelectedMode,
  } = useAnswerController({
    resolvedChallengeId,
    routeMode: resolvedRouteMode,
  });

  useEffect(() => {
    headerProgress.value = withTiming(isHeaderCollapsed ? 0 : 1, {
      duration: 220,
      easing: Easing.out(Easing.cubic),
    });
  }, [headerProgress, isHeaderCollapsed]);

  const headerAnimatedStyle = useAnimatedStyle(() => ({
    opacity: headerProgress.value,
    maxHeight: 176 * headerProgress.value,
    transform: [
      {
        translateY: (1 - headerProgress.value) * -8,
      },
    ],
  }));

  useEffect(() => {
    debugLog("answer", "mounted", {
      params,
      resolvedChallengeId,
      routeMode: resolvedRouteMode,
      timestamp: Date.now(),
    });

    return () => {
      debugLog("answer", "unmounted", {
        resolvedChallengeId,
        timestamp: Date.now(),
      });
    };
    // We intentionally want a one-time mount/unmount signal here.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    debugLog("answer", "params changed", {
      params,
      resolvedChallengeId,
      routeMode: resolvedRouteMode,
    });
  }, [params, resolvedChallengeId, resolvedRouteMode]);

  function handleToggleHeader() {
    setHeaderCollapsed((current) => !current);
  }

  function handleOpenAssistantInput() {
    Keyboard.dismiss();
    setAssistantInputOpen(true);
  }

  return (
    <View className="flex-1 bg-background">
      <View
        className="border-b border-border bg-background px-5"
        style={{ paddingTop: insets.top }}
      >
        <Animated.View className="overflow-hidden" style={headerAnimatedStyle}>
          <View className="gap-1 pb-1">
            <View className="gap-1">
              <Text className="text-xl font-semibold tracking-tight text-foreground">
                {isChallengeLoading
                  ? "loading challenge..."
                  : (challenge?.title ?? "no active challenge")}
              </Text>
              <ScrollView
                style={{ maxHeight: 120 }}
                showsVerticalScrollIndicator={isHeaderTeaserOverflowing}
                onContentSizeChange={(_, contentHeight) => {
                  setHeaderTeaserOverflowing(contentHeight > 120);
                }}
              >
                <Text className="pr-2 text-sm leading-6 text-muted">
                  {isChallengeLoading
                    ? ""
                    : (challenge?.teaser ??
                      "Generate or resume a challenge to start working here.")}
                </Text>
              </ScrollView>
            </View>
          </View>
        </Animated.View>

        <View className="flex-row items-center justify-center pb-1">
          <HeaderToggle
            collapsed={isHeaderCollapsed}
            onPress={handleToggleHeader}
          />
        </View>
      </View>

      <AssistantHeader
        mode={selectedMode}
        guidance={assistantGuidance}
        latestMessage={latestAssistantMessage}
        status={assistantStatus}
        onPress={handleOpenAssistantInput}
      />

      <View className="flex-1">
        <KeyboardAwareScrollView
          className="flex-1 px-5 pt-4"
          contentContainerStyle={{
            paddingBottom: insets.bottom + 16,
            gap: 16,
            flexGrow: 1,
          }}
          extraKeyboardSpace={12}
          bottomOffset={insets.bottom}
          showsVerticalScrollIndicator={false}
        >
          <View className="flex-1 gap-4">
            <TextField className="flex-1">
              <View className="mb-1 flex-row items-center justify-between gap-3 px-1">
                <View className="flex-1 flex-row items-center">
                  <Label>answer</Label>
                  <View className="flex-1" />
                </View>

                <HeaderMenuButton
                  challenge={challenge}
                  isChallengeLoading={isChallengeLoading}
                  selectedMode={selectedMode}
                  availableModels={availableModels}
                  selectedModelId={selectedModelId}
                  onSelectMode={(mode) => {
                    setSelectedMode(mode);
                  }}
                  onSelectModel={(model) => {
                    handleSelectModel(model.id);
                  }}
                  onSkip={handleSkip}
                  onSave={handleSave}
                  onDone={handleDone}
                  isActionDisabled={!canInteractWithChallenge}
                />
              </View>
              <Input
                multiline
                numberOfLines={18}
                placeholder={
                  "Work through the problem here.\n\n1. State the product and user-facing goal.\n2. Outline the main components and data flow.\n3. Call out trade-offs, bottlenecks, failure modes, and what you would validate next.\n4. Think in multiple passes before locking the design."
                }
                value={notesDraft}
                onChangeText={setNotesDraft}
                scrollEnabled
                className="flex-1 items-start rounded-[var(--radius)] border border-border bg-surface px-4 py-4"
                textAlignVertical="top"
                isDisabled={!canInteractWithChallenge}
              />
            </TextField>

            {selectedMode === "reveal" && revealAnswer ? (
              <RevealAnswerCard answer={revealAnswer} visible />
            ) : null}
          </View>
        </KeyboardAwareScrollView>
      </View>

      <AssistantSheet
        visible={isAssistantInputOpen}
        mode={selectedMode}
        assistantHistory={assistantHistory}
        assistantMessage={assistantMessage}
        isAssistantLoading={isAssistantLoading}
        canInteractWithChallenge={canInteractWithChallenge}
        onClose={() => setAssistantInputOpen(false)}
        onChangeMessage={(value: string) => {
          setAssistantMessage(value);
          setAssistantDraft(value);
        }}
        onSubmit={handleAssistantSubmit}
      />
    </View>
  );
}
