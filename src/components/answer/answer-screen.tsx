import { useLocalSearchParams } from "expo-router";
import { Input, Label, TextField } from "heroui-native";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Keyboard, Pressable, ScrollView, Text, View } from "react-native";
import Animated, { Easing, useAnimatedStyle, useSharedValue, withTiming } from "react-native-reanimated";
import { KeyboardAwareScrollView } from "react-native-keyboard-controller";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import {
  AssistantHeader,
} from "@/components/answer/assistant-header";
import {
  getLatestAssistantMessage,
  mapConversationHistoryToChat,
  type AssistantChatMessage,
} from "@/components/answer/assistant-history";
import { HeaderMenuButton } from "@/components/answer/header-menu-button";
import { RevealAnswerCard } from "@/components/answer/reveal-answer-card";
import { AssistantSheet } from "@/components/answer/assistant-sheet";
import { useAnswerActions } from "@/components/answer/use-answer-actions";
import { useAnswerScreenState } from "@/components/answer/use-answer-screen-state";
import { useCoachGuidance } from "@/components/answer/use-coach-guidance";
import { useAnswerCompletionActions } from "@/components/answer/use-answer-completion-actions";
import { useAssistantFieldState } from "@/components/answer/use-assistant-field-state";
import { useChallengeSessionPersistence } from "@/components/answer/use-challenge-session-persistence";
import { useRevealOutput } from "@/components/answer/use-reveal-output";
import { cn } from "@/lib/cn";
import { debugLog } from "@/lib/debug";
import { markChallengeInProgress, selectModel } from "@/lib/storage/repository";
import type { ChallengeConversationTurn } from "@/lib/storage/types";
import type { ChallengeMode } from "@/lib/widgets/types";

function HeaderToggle({
  collapsed,
  onPress,
}: {
  collapsed: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable className="items-center px-3 py-[1.65]" onPress={onPress}>
      <View className="items-center gap-1">
        <View className="h-4 w-16 items-center justify-center">
          <View className="relative h-3 w-13">
            <View
              className={cn(
                "absolute left-1 top-1 h-[2px] w-6 rounded-full bg-border",
                collapsed ? "rotate-12" : "-rotate-12",
              )}
            />
            <View
              className={cn(
                "absolute right-1 top-1 h-[2px] w-6 rounded-full bg-border",
                collapsed ? "-rotate-12" : "rotate-12",
              )}
            />
          </View>
        </View>
      </View>
    </Pressable>
  );
}

function commitAssistantTurn({
  currentHistory,
  mode,
  userText,
  assistantText,
  assistantAnswer,
}: {
  currentHistory: ChallengeConversationTurn[];
  mode: Extract<ChallengeMode, "coach" | "reveal">;
  userText?: string;
  assistantText: string;
  assistantAnswer?: string;
}) {
  const assistantTurnId = `assistant-${Date.now()}`;
  const nextHistory = [...currentHistory];

  if (userText) {
    nextHistory.push({
      id: `user-${assistantTurnId}`,
      role: "user",
      mode,
      text: userText,
      createdAt: new Date().toISOString(),
    });
  }

  nextHistory.push({
    id: assistantTurnId,
    role: "assistant",
    mode,
    text: assistantText,
    answer: assistantAnswer,
    createdAt: new Date().toISOString(),
  });

  return nextHistory;
}

function normalizeCoachText(value: string) {
  return value.trim().replace(/\s+/g, " ");
}

export function AnswerScreen() {
  const insets = useSafeAreaInsets();
  const params = useLocalSearchParams<{
    mode?: string;
    challengeId?: string;
  }>();
  const routeMode = useMemo<ChallengeMode | null>(() => {
    if (
      params.mode === "solo" ||
      params.mode === "coach" ||
      params.mode === "reveal"
    ) {
      return params.mode;
    }

    return null;
  }, [params.mode]);
  
  const [selectedMode, setSelectedMode] = useState<ChallengeMode>(routeMode ?? "coach");
  const [notesDraft, setNotesDraft] = useState("");
  const [assistantDraft, setAssistantDraft] = useState("");
  const [, setUpdatedAt] = useState(new Date().toISOString());
  const [isHeaderCollapsed, setHeaderCollapsed] = useState(false);
  const [isAssistantInputOpen, setAssistantInputOpen] = useState(false);
  const [assistantMessage, setAssistantMessage] = useState("");
  const coachField = useAssistantFieldState();
  const revealField = useAssistantFieldState();
  const [assistantHistory, setAssistantHistory] = useState<AssistantChatMessage[]>([]);
  const [conversationHistory, setConversationHistory] = useState<
    ChallengeConversationTurn[]
  >([]);
  const [isCoachLoading, setCoachLoading] = useState(false);
  const [isRevealLoading, setRevealLoading] = useState(false);
  const [isHeaderTeaserOverflowing, setHeaderTeaserOverflowing] = useState(false);
  const resolvedChallengeId = params.challengeId ?? null;
  const headerProgress = useSharedValue(isHeaderCollapsed ? 0 : 1);
  const revealRequestIdRef = useRef(0);

  useEffect(() => {
    headerProgress.value = withTiming(isHeaderCollapsed ? 0 : 1, {
      duration: 220,
      easing: Easing.out(Easing.cubic),
    });
  }, [headerProgress, isHeaderCollapsed]);

  const headerAnimatedStyle = useAnimatedStyle(() => ({
    opacity: headerProgress.value,
    maxHeight: 180 * headerProgress.value,
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
      routeMode,
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
      routeMode,
    });
  }, [params, resolvedChallengeId, routeMode]);

  const resetAnswerState = useCallback(
    (nextMode: ChallengeMode = routeMode ?? "coach") => {
      setChallenge(null);
      setSelectedMode(nextMode);
      setNotesDraft("");
      setAssistantDraft("");
      setUpdatedAt(new Date().toISOString());
      setConversationHistory([]);
      setAssistantHistory([]);
      coachField.reset(nextMode === "coach" ? "idle" : "done");
      revealField.reset(nextMode === "reveal" ? "idle" : "done");
      setAssistantInputOpen(false);
      setAssistantMessage("");
    },
    [coachField, revealField, routeMode],
  );

  const normalizedNotesDraft = useMemo(
    () => normalizeCoachText(notesDraft),
    [notesDraft],
  );

  const assistantThreadMode = selectedMode === "reveal" ? "reveal" : "coach";
  const isAssistantLoading =
    selectedMode === "coach"
      ? isCoachLoading
      : selectedMode === "reveal"
        ? isRevealLoading
        : false;

  const beginRevealRequest = useCallback(() => {
    revealRequestIdRef.current += 1;
    return revealRequestIdRef.current;
  }, []);

  const invalidateRevealRequest = useCallback(() => {
    revealRequestIdRef.current += 1;
  }, []);

  const isRevealRequestCurrent = useCallback(
    (requestId: number) => revealRequestIdRef.current === requestId,
    [],
  );

  const { persistSession, syncPersistedDraftSnapshot } = useChallengeSessionPersistence({
    resolvedChallengeId,
    selectedMode,
    notesDraft,
    assistantDraft,
    conversationHistory,
  });

  const {
    availableModels,
    challenge,
    isChallengeLoading,
    refreshResolvedChallenge,
    selectedModelId,
    setChallenge,
    setSelectedModelId,
  } = useAnswerScreenState({
    resolvedChallengeId,
    routeMode,
    resetAnswerState,
    coachField,
    revealField,
    syncPersistedDraftSnapshot,
    setSelectedMode,
    setNotesDraft,
    setAssistantDraft,
    setAssistantMessage,
    setUpdatedAt,
    setConversationHistory,
  });

  const canInteractWithChallenge = Boolean(
    resolvedChallengeId && challenge && !isChallengeLoading,
  );

  const { invalidateCoachRequest, requestCoachGuidance } = useCoachGuidance({
    selectedMode,
    resolvedChallengeId,
    hasChallenge: Boolean(challenge),
    normalizedNotesDraft,
    conversationHistory,
    isCoachLoading,
    coachField,
    setCoachLoading,
    setConversationHistory,
    commitAssistantTurn,
    persistSession,
  });

  useEffect(() => {
    if (selectedMode !== "coach") {
      invalidateCoachRequest();
      setCoachLoading(false);
    }

    if (selectedMode !== "reveal") {
      invalidateRevealRequest();
      setRevealLoading(false);
    }
  }, [invalidateCoachRequest, invalidateRevealRequest, selectedMode]);

  useEffect(() => {
    if (selectedMode === "solo") {
      setAssistantHistory([]);
      return;
    }

    setAssistantHistory(mapConversationHistoryToChat(conversationHistory, assistantThreadMode));
  }, [assistantThreadMode, conversationHistory, selectedMode]);

  useEffect(() => {
    if (!resolvedChallengeId || !challenge) {
      return;
    }

    debugLog("answer", "marking challenge in progress", {
      resolvedChallengeId,
      selectedMode,
    });

    void markChallengeInProgress(resolvedChallengeId, selectedMode);
    void persistSession({ selectedMode });
  }, [challenge, persistSession, resolvedChallengeId, selectedMode]);

  useRevealOutput({
    selectedMode,
    resolvedChallengeId,
    hasChallenge: Boolean(challenge),
    conversationHistory,
    revealField,
    isRevealLoading,
    setRevealLoading,
    setConversationHistory,
    commitAssistantTurn,
    persistSession,
    beginRevealRequest,
    isRevealRequestCurrent,
  });

  function handleToggleHeader() {
    setHeaderCollapsed((current) => !current);
  }

  const { handleSkip, handleSave, handleDone } = useAnswerCompletionActions({
    canInteractWithChallenge,
    resolvedChallengeId,
    selectedMode,
    persistSession: () => persistSession(),
    refreshResolvedChallenge,
    resetAnswerState,
  });

  const { handleAssistantSubmit } = useAnswerActions({
    assistantMessage,
    canInteractWithChallenge,
    resolvedChallengeId,
    selectedMode,
    conversationHistory,
    requestCoachGuidance,
    persistSession,
    setAssistantHistory,
    setConversationHistory,
    setCoachLoading,
    setRevealLoading,
    setAssistantMessage,
    mapConversationHistoryToChat: (history) =>
      mapConversationHistoryToChat(history, assistantThreadMode),
    commitAssistantTurn,
    coachField,
    revealField,
    beginRevealRequest,
    isRevealRequestCurrent,
  });

  const latestAssistantMessage = useMemo(
    () => getLatestAssistantMessage(assistantHistory, assistantThreadMode),
    [assistantHistory, assistantThreadMode],
  );

  const assistantGuidance =
    selectedMode === "coach"
      ? coachField.text
      : selectedMode === "reveal"
        ? revealField.text
        : null;

  const assistantStatus =
    selectedMode === "coach"
      ? coachField.status
      : selectedMode === "reveal"
        ? revealField.status
        : undefined;

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
              <Text className="text-lg font-semibold tracking-tight text-foreground">
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
                <Text className="pr-2 text-sm leading-5 text-muted">
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
              <View className="mb-1 mt-[-4px] flex-row items-center justify-between gap-3 px-1">
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
                    setSelectedModelId(model.id);
                    void selectModel(model.id);
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
                className="flex-1 items-start rounded-[28px] border border-border bg-surface px-4 py-4"
                textAlignVertical="top"
                isDisabled={!canInteractWithChallenge}
              />
            </TextField>

            {selectedMode === "reveal" && revealField.answer ? (
              <RevealAnswerCard answer={revealField.answer} visible />
            ) : null}

            {/* TODO: save-for-later action should persist this session and remove it from the active flow until reopened */}
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
          const nextValue = value;
          setAssistantMessage(nextValue);
          setAssistantDraft(nextValue);
        }}
        onSubmit={handleAssistantSubmit}
      />
    </View>
  );
}
