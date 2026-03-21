import { useLocalSearchParams } from "expo-router";
import { Input, Label, TextField } from "heroui-native";
import { useCallback, useEffect, useMemo, useState } from "react";
import { Keyboard, Pressable, ScrollView, Text, View } from "react-native";
import Animated, { Easing, useAnimatedStyle, useSharedValue, withTiming } from "react-native-reanimated";
import { KeyboardAwareScrollView } from "react-native-keyboard-controller";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import {
  AssistantHeader,
} from "@/components/answer/assistant-header";
import { HeaderMenuButton } from "@/components/answer/header-menu-button";
import { RevealAnswerCard } from "@/components/answer/reveal-answer-card";
import { AssistantSheet } from "@/components/answer/assistant-sheet";
import { useAnswerActions } from "@/components/answer/use-answer-actions";
import { useAnswerCompletionActions } from "@/components/answer/use-answer-completion-actions";
import { useAssistantFieldState } from "@/components/answer/use-assistant-field-state";
import {
  streamCoachGuidance,
  streamRevealAnswer,
} from "@/lib/ai/prompt-runtime";
import { cn } from "@/lib/cn";
import { debugLog } from "@/lib/debug";
import { subscribeToModelsRefresh } from "@/lib/models-refresh";
import { subscribeToSettingsRefresh } from "@/lib/settings-refresh";
import {
  ensureDefaultModels,
  ensureDefaultSettings,
  getChallengeById,
  getChallengeSession,
  listModels,
  markChallengeInProgress,
  refreshReadyChallengeExpirations,
  selectModel,
  upsertChallengeSession,
} from "@/lib/storage/repository";
import type {
  CoachTriggerReason,
  ChallengeConversationTurn,
  ChallengeRecord,
  ChallengeSessionRecord,
  ModelRecord,
} from "@/lib/storage/types";
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

const AUTO_COACH_MIN_NOTES_CHARS = 180;
const AUTO_COACH_MIN_NEW_CHARS = 80;
const AUTO_COACH_IDLE_MS = 2500;
const AUTO_COACH_COOLDOWN_MS = 15000;

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
  const [conversationSummary, setConversationSummary] = useState("");
  const [, setUpdatedAt] = useState(new Date().toISOString());
  const [isHeaderCollapsed, setHeaderCollapsed] = useState(false);
  const [isAssistantInputOpen, setAssistantInputOpen] = useState(false);
  const [assistantMessage, setAssistantMessage] = useState("");
  const [selectedModelId, setSelectedModelId] = useState<string | undefined>();
  const [availableModels, setAvailableModels] = useState<ModelRecord[]>([]);
  const [challenge, setChallenge] = useState<ChallengeRecord | null>(null);
  const coachField = useAssistantFieldState();
  const revealField = useAssistantFieldState();
  const [assistantHistory, setAssistantHistory] = useState<
    { id: string; role: "coach" | "you"; text: string }[]
  >([]);
  const [conversationHistory, setConversationHistory] = useState<
    ChallengeConversationTurn[]
  >([]);
  const [lastAutoCoachAt, setLastAutoCoachAt] = useState<number | null>(null);
  const [lastAutoCoachNotesSnapshot, setLastAutoCoachNotesSnapshot] = useState("");
  const [isAssistantLoading, setAssistantLoading] = useState(false);
  const [isChallengeLoading, setChallengeLoading] = useState(true);
  const [isHeaderTeaserOverflowing, setHeaderTeaserOverflowing] = useState(false);
  const resolvedChallengeId = params.challengeId ?? null;
  const headerProgress = useSharedValue(isHeaderCollapsed ? 0 : 1);

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
      setConversationSummary("");
      setUpdatedAt(new Date().toISOString());
      setConversationHistory([]);
      setAssistantHistory([]);
      coachField.reset(nextMode === "coach" ? "idle" : "done");
      revealField.reset(nextMode === "reveal" ? "idle" : "done");
      setLastAutoCoachAt(null);
      setLastAutoCoachNotesSnapshot("");
      setAssistantInputOpen(false);
      setAssistantMessage("");
    },
    [coachField, revealField, routeMode],
  );

  function isActiveAnswerChallenge(record: ChallengeRecord | null | undefined) {
    return record?.lifecycle === "ready" || record?.lifecycle === "in_progress";
  }

  async function refreshResolvedChallenge() {
    if (!resolvedChallengeId) {
      resetAnswerState();
      return null;
    }

    const latestChallenge = await getChallengeById(resolvedChallengeId);
    if (!isActiveAnswerChallenge(latestChallenge)) {
      resetAnswerState();
      return null;
    }

    setChallenge(latestChallenge);
    return latestChallenge;
  }

  const canInteractWithChallenge = Boolean(
    resolvedChallengeId && challenge && !isChallengeLoading,
  );

  function mapConversationHistoryToChat(history: ChallengeConversationTurn[]) {
    return history.map((turn) => ({
      id: turn.id,
      role: turn.role === "assistant" ? ("coach" as const) : ("you" as const),
      text: turn.text,
    }));
  }

  const normalizedNotesDraft = useMemo(
    () => normalizeCoachText(notesDraft),
    [notesDraft],
  );

  const persistSession = useCallback(
    async (overrides: Partial<ChallengeSessionRecord> = {}) => {
      const nextUpdatedAt = overrides.updatedAt ?? new Date().toISOString();

      await upsertChallengeSession({
        challengeId: resolvedChallengeId ?? "",
        selectedMode: overrides.selectedMode ?? selectedMode,
        notesDraft: overrides.notesDraft ?? notesDraft,
        conversationSummary:
          overrides.conversationSummary ?? conversationSummary,
        conversationHistory:
          overrides.conversationHistory ?? conversationHistory,
        updatedAt: nextUpdatedAt,
      });
    },
    [
      conversationHistory,
      conversationSummary,
      notesDraft,
      resolvedChallengeId,
      selectedMode,
    ],
  );

  const requestCoachGuidance = useCallback(
    async ({
      trigger,
      latestUserRequest,
      appendToHistory = false,
      onPartialGuidance,
    }: {
      trigger: CoachTriggerReason;
      latestUserRequest?: string;
      appendToHistory?: boolean;
      onPartialGuidance?: (partialText: string) => void;
    }) => {
      if (!resolvedChallengeId) {
        return null;
      }

      coachField.begin();
      let streamedText = "";

      const result = await streamCoachGuidance(resolvedChallengeId, {
        coachTrigger: trigger,
        latestUserRequest,
        onTextDelta: (textDelta) => {
          streamedText += textDelta;
          coachField.streamText(streamedText);
          onPartialGuidance?.(streamedText);
        },
      });

      coachField.finish(result.output.guidance);
      revealField.reset("idle");

      if (appendToHistory) {
        setConversationHistory((current) => {
          const lastAssistantTurn = [...current]
            .reverse()
            .find((turn) => turn.role === "assistant" && turn.mode === "coach");

          if (lastAssistantTurn?.text === result.output.guidance) {
            return current;
          }

          const nextHistory = commitAssistantTurn({
            currentHistory: current,
            mode: "coach",
            assistantText: result.output.guidance,
          });

          setAssistantHistory(mapConversationHistoryToChat(nextHistory));
          void persistSession({ conversationHistory: nextHistory });
          return nextHistory;
        });
      }

      return result;
    },
    [coachField, persistSession, resolvedChallengeId, revealField],
  );

  const loadModelState = useCallback(async () => {
    await ensureDefaultModels();
    const [models, settings] = await Promise.all([
      listModels({ includeDisabled: false }),
      ensureDefaultSettings(),
    ]);

    setAvailableModels(models);
    setSelectedModelId(settings.selectedModelId ?? models[0]?.id);
  }, []);

  useEffect(() => {
    let isMounted = true;

    async function loadScreenState() {
      setChallengeLoading(true);
      debugLog("answer", "loading screen state", {
        resolvedChallengeId,
      });

      const [, models, settings, existingChallenge, existingSession] =
        await Promise.all([
          ensureDefaultModels(),
          listModels({ includeDisabled: false }),
          ensureDefaultSettings(),
          resolvedChallengeId
            ? getChallengeById(resolvedChallengeId)
            : Promise.resolve(null),
          resolvedChallengeId
            ? getChallengeSession(resolvedChallengeId)
            : Promise.resolve(null),
        ]);
      await refreshReadyChallengeExpirations(settings);

      if (!isMounted) {
        return;
      }

      debugLog("answer", "loaded screen state", {
        resolvedChallengeId,
        foundChallenge: Boolean(existingChallenge),
        foundSession: Boolean(existingSession),
        selectedModelId: settings.selectedModelId,
      });

      setAvailableModels(models);
      setSelectedModelId(settings.selectedModelId ?? models[0]?.id);

      if (!isActiveAnswerChallenge(existingChallenge)) {
        resetAnswerState();
        setChallengeLoading(false);
        return;
      }

      setChallenge(existingChallenge);

      if (existingSession) {
        setSelectedMode(
          existingSession.selectedMode ?? settings.preferredMode ?? routeMode ?? "coach",
        );
        setNotesDraft(existingSession.notesDraft ?? "");
        setConversationSummary(existingSession.conversationSummary ?? "");
        setUpdatedAt(existingSession.updatedAt);
        setConversationHistory(existingSession.conversationHistory);
        setAssistantHistory(
          mapConversationHistoryToChat(existingSession.conversationHistory),
        );
      } else {
        setSelectedMode(settings.preferredMode ?? routeMode ?? "coach");
        setNotesDraft("");
        setConversationSummary("");
        setUpdatedAt(new Date().toISOString());
        setConversationHistory([]);
        setAssistantHistory([]);
        coachField.reset();
        revealField.reset();
      }

      setChallengeLoading(false);
    }

    void loadScreenState();

    return () => {
      isMounted = false;
    };
  }, [coachField, resetAnswerState, resolvedChallengeId, revealField, routeMode]);

  useEffect(() => {
    return subscribeToModelsRefresh(() => {
      void loadModelState();
    });
  }, [loadModelState]);

  useEffect(() => {
    return subscribeToSettingsRefresh(() => {
      void loadModelState();
    });
  }, [loadModelState]);

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

  useEffect(() => {
    if (selectedMode === "solo") {
      coachField.reset();
      revealField.reset();
      return;
    }

    if (selectedMode === "coach") {
      revealField.reset();
      return;
    }

    if (!resolvedChallengeId || !challenge) {
      return;
    }

    let isMounted = true;

    async function loadRevealOutput() {
      if (selectedMode !== "reveal") {
        return;
      }

      setAssistantLoading(true);
      debugLog("answer", "loading assistant output", {
        resolvedChallengeId,
        selectedMode,
      });

      try {
        revealField.begin();
        let streamedText = "";

        const result = await streamRevealAnswer(resolvedChallengeId!, {
          onTextDelta: (textDelta) => {
            streamedText += textDelta;
            revealField.streamRevealDraft(streamedText);
          },
        });
        if (!isMounted) {
          return;
        }

        revealField.finish(result.output.guidance, result.output.answer);
        debugLog("answer", "loaded reveal answer", {
          resolvedChallengeId,
        });
      } catch (error) {
        debugLog("answer", "assistant output failed", {
          resolvedChallengeId,
          selectedMode,
          error: error instanceof Error ? error.message : String(error),
        });
        if (!isMounted) {
          return;
        }

        revealField.fail(
          error instanceof Error ? error.message : "assistant request failed",
        );
      } finally {
        if (isMounted) {
          setAssistantLoading(false);
        }
      }
    }

    void loadRevealOutput();

    return () => {
      isMounted = false;
    };
  }, [challenge, coachField, resolvedChallengeId, revealField, selectedMode]);

  useEffect(() => {
    if (selectedMode !== "coach") {
      return;
    }

    if (!resolvedChallengeId || !challenge || isAssistantLoading) {
      return;
    }

    const noteLength = normalizedNotesDraft.length;
    if (noteLength < AUTO_COACH_MIN_NOTES_CHARS) {
      return;
    }

    const lastCoachTurn = [...conversationHistory]
      .reverse()
      .find((turn) => turn.role === "assistant" && turn.mode === "coach");
    const trigger: CoachTriggerReason = lastCoachTurn
      ? "auto_after_progress"
      : "auto_initial";
    const newCharsSinceLastSnapshot = Math.max(
      0,
      noteLength - lastAutoCoachNotesSnapshot.length,
    );

    if (
      trigger === "auto_after_progress" &&
      newCharsSinceLastSnapshot < AUTO_COACH_MIN_NEW_CHARS
    ) {
      return;
    }

    if (
      lastAutoCoachAt != null &&
      Date.now() - lastAutoCoachAt < AUTO_COACH_COOLDOWN_MS
    ) {
      return;
    }

    const timeout = setTimeout(() => {
      void (async () => {
        setAssistantLoading(true);

        try {
          const result = await requestCoachGuidance({
            trigger,
            appendToHistory: true,
          });

          if (!result) {
            return;
          }

          setLastAutoCoachAt(Date.now());
          setLastAutoCoachNotesSnapshot(normalizedNotesDraft);
          debugLog("answer", "loaded coach guidance", {
            resolvedChallengeId,
            trigger,
          });
        } catch (error) {
          debugLog("answer", "assistant output failed", {
            resolvedChallengeId,
            selectedMode,
            error: error instanceof Error ? error.message : String(error),
          });
          coachField.fail(
            error instanceof Error ? error.message : "assistant request failed",
          );
        } finally {
          setAssistantLoading(false);
        }
      })();
    }, AUTO_COACH_IDLE_MS);

    return () => clearTimeout(timeout);
  }, [
    challenge,
    conversationHistory,
    coachField,
    isAssistantLoading,
    lastAutoCoachAt,
    lastAutoCoachNotesSnapshot.length,
    normalizedNotesDraft,
    requestCoachGuidance,
    resolvedChallengeId,
    selectedMode,
  ]);

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
    setAssistantLoading,
    setAssistantMessage,
    mapConversationHistoryToChat,
    commitAssistantTurn,
    coachField,
    revealField,
  });

  const latestAssistantMessage = useMemo(
    () => [...assistantHistory].reverse().find((message) => message.role === "coach")?.text ?? null,
    [assistantHistory],
  );

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
        guidance={
          selectedMode === "coach"
            ? coachField.text
            : selectedMode === "reveal"
              ? revealField.text
              : null
        }
        latestMessage={latestAssistantMessage}
        status={
          selectedMode === "coach"
            ? coachField.status
            : selectedMode === "reveal"
              ? revealField.status
              : undefined
        }
        onPress={() => {
          Keyboard.dismiss();
          setAssistantInputOpen(true);
        }}
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
              <Pressable
                className="flex-1 flex-row items-center"
                onPress={() => {}}
              >
                <Label>answer</Label>
                <View className="flex-1" />
              </Pressable>

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
              onChangeText={(value) => {
                setNotesDraft(value);
                if (canInteractWithChallenge && resolvedChallengeId) {
                  void persistSession({ notesDraft: value });
                }
              }}
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
          setConversationSummary(nextValue);
          if (canInteractWithChallenge && resolvedChallengeId) {
            void persistSession({ conversationSummary: nextValue });
          }
        }}
        onSubmit={handleAssistantSubmit}
      />
    </View>
  );
}
