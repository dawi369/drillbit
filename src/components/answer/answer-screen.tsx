import { router, useLocalSearchParams } from "expo-router";
import {
  Button,
  Input,
  Label,
  Menu,
  Separator,
  SubMenu,
  TextField,
} from "heroui-native";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Alert, Modal, Pressable, ScrollView, Text, View } from "react-native";
import Animated, {
  Easing,
  useAnimatedStyle,
  useSharedValue,
  withTiming,
} from "react-native-reanimated";
import {
  KeyboardAwareScrollView,
  KeyboardChatScrollView,
  KeyboardStickyView,
} from "react-native-keyboard-controller";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { MODE_OPTIONS } from "@/constants/params";
import {
  generateCoachGuidance,
  generateRevealAnswer,
  summarizeChallengeSession,
} from "@/lib/ai/prompt-runtime";
import { cn } from "@/lib/cn";
import { debugLog } from "@/lib/debug";
import { subscribeToModelsRefresh } from "@/lib/models-refresh";
import { subscribeToSettingsRefresh } from "@/lib/settings-refresh";
import {
  completeChallenge,
  ensureDefaultModels,
  ensureDefaultSettings,
  getChallengeById,
  getChallengeSession,
  listModels,
  markChallengeInProgress,
  refreshReadyChallengeExpirations,
  selectModel,
  skipChallenge,
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

function MetaPill({ label }: { label: string }) {
  return (
    <View className="rounded-full border border-border bg-surface-secondary px-2 py-0.5">
      <Text className="text-[10px] font-medium uppercase tracking-[1px] text-foreground">
        {label}
      </Text>
    </View>
  );
}

function HeaderMenuButton({
  challenge,
  isChallengeLoading,
  selectedMode,
  availableModels,
  selectedModelId,
  onSelectMode,
  onSelectModel,
  onSkip,
  onSave,
  onDone,
  isActionDisabled,
}: {
  challenge: ChallengeRecord | null;
  isChallengeLoading: boolean;
  selectedMode: ChallengeMode;
  availableModels: ModelRecord[];
  selectedModelId?: string;
  onSelectMode: (mode: ChallengeMode) => void;
  onSelectModel: (model: ModelRecord) => void;
  onSkip: () => void;
  onSave: () => void;
  onDone: () => void;
  isActionDisabled: boolean;
}) {
  const selectedModel = availableModels.find((model) => model.id === selectedModelId);
  const selectedModeOption = MODE_OPTIONS.find((option) => option.value === selectedMode);
  const [openSubMenu, setOpenSubMenu] = useState<"mode" | "model" | null>(null);
  const openSubMenuTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    return () => {
      if (openSubMenuTimeoutRef.current) {
        clearTimeout(openSubMenuTimeoutRef.current);
      }
    };
  }, []);

  function handleSubMenuOpenChange(nextKey: "mode" | "model", open: boolean) {
    if (!open) {
      setOpenSubMenu((current) => (current === nextKey ? null : current));
      return;
    }

    if (openSubMenu && openSubMenu !== nextKey) {
      setOpenSubMenu(null);
      if (openSubMenuTimeoutRef.current) {
        clearTimeout(openSubMenuTimeoutRef.current);
      }
      openSubMenuTimeoutRef.current = setTimeout(() => {
        setOpenSubMenu(nextKey);
        openSubMenuTimeoutRef.current = null;
      }, 40);
      return;
    }

    if (openSubMenuTimeoutRef.current) {
      clearTimeout(openSubMenuTimeoutRef.current);
      openSubMenuTimeoutRef.current = null;
    }

    setOpenSubMenu(nextKey);
  }

  return (
    <Menu>
      <Menu.Trigger asChild>
        <Button size="sm" variant="primary">
          <Button.Label>menu</Button.Label>
        </Button>
      </Menu.Trigger>
      <Menu.Portal>
        <Menu.Overlay />
        <Menu.Content
          presentation="popover"
          placement="bottom"
          align="end"
          width={280}
        >
          <Menu.Label className="px-1 pb-1">challenge</Menu.Label>
          <View className="flex-row flex-wrap justify-center gap-2 px-2 pb-3 pt-1">
            <MetaPill
              label={
                isChallengeLoading
                  ? "loading"
                  : (challenge?.topic ?? "no topic")
              }
            />
            <MetaPill
              label={
                isChallengeLoading
                  ? "loading"
                  : (challenge?.difficulty ?? "no difficulty")
              }
            />
          </View>

          <Separator className="mx-3 my-2 h-px opacity-100" />

          <View style={{ zIndex: openSubMenu === "mode" ? 20 : 0 }}>
            <SubMenu
              isOpen={openSubMenu === "mode"}
              onOpenChange={(open) => {
                handleSubMenuOpenChange("mode", open);
              }}
            >
              <SubMenu.Trigger textValue="mode">
                <View className="flex-1">
                  <Text className="text-sm font-medium text-foreground">mode</Text>
                  <Text className="text-xs text-muted">
                    {selectedModeOption?.label ?? selectedMode}
                  </Text>
                </View>
                <SubMenu.TriggerIndicator />
              </SubMenu.Trigger>
              <SubMenu.Content className="z-20">
                <Menu.Group
                  selectionMode="single"
                  selectedKeys={new Set([selectedMode])}
                  onSelectionChange={(keys) => {
                    const nextMode = Array.from(keys)[0];
                    if (
                      nextMode === "solo" ||
                      nextMode === "coach" ||
                      nextMode === "reveal"
                    ) {
                      onSelectMode(nextMode);
                      setOpenSubMenu(null);
                    }
                  }}
                >
                  {MODE_OPTIONS.map((option) => (
                    <Menu.Item key={option.value} id={option.value}>
                      <Menu.ItemIndicator variant="dot" />
                      <View className="flex-1">
                        <Menu.ItemTitle>{option.label}</Menu.ItemTitle>
                        <Menu.ItemDescription>
                          {option.description}
                        </Menu.ItemDescription>
                      </View>
                    </Menu.Item>
                  ))}
                </Menu.Group>
              </SubMenu.Content>
            </SubMenu>
          </View>

          <Separator className="mx-3 my-2 h-px opacity-100" />

          <View style={{ zIndex: openSubMenu === "model" ? 20 : 0 }}>
            <SubMenu
              isOpen={openSubMenu === "model"}
              onOpenChange={(open) => {
                handleSubMenuOpenChange("model", open);
              }}
            >
              <SubMenu.Trigger textValue="models">
                <View className="flex-1">
                  <Text className="text-sm font-medium text-foreground">models</Text>
                  <Text className="text-xs text-muted">
                    {selectedModel?.label ?? "no model selected"}
                  </Text>
                </View>
                <SubMenu.TriggerIndicator />
              </SubMenu.Trigger>
              <SubMenu.Content className="z-20">
                <Menu.Group
                  selectionMode="single"
                  selectedKeys={selectedModelId ? new Set([selectedModelId]) : new Set()}
                  onSelectionChange={(keys) => {
                    const nextModelId = Array.from(keys)[0];
                    const nextModel = availableModels.find(
                      (model) => model.id === nextModelId,
                    );
                    if (nextModel) {
                      onSelectModel(nextModel);
                      setOpenSubMenu(null);
                    }
                  }}
                >
                  {availableModels.map((model) => (
                    <Menu.Item key={model.id} id={model.id}>
                      <Menu.ItemIndicator variant="dot" />
                      <View className="flex-1">
                        <Menu.ItemTitle>{model.label}</Menu.ItemTitle>
                        <Menu.ItemDescription>{model.remoteId}</Menu.ItemDescription>
                      </View>
                    </Menu.Item>
                  ))}
                </Menu.Group>
              </SubMenu.Content>
            </SubMenu>
          </View>

          <Separator className="mx-3 my-2 h-px opacity-100" />

          <Menu.Label className="px-1 pb-1 pt-2">actions</Menu.Label>
          <View className="flex-row flex-wrap justify-center gap-2 px-2 pb-2 pt-1">
            <Button size="sm" variant="tertiary" onPress={onSkip} isDisabled={isActionDisabled}>
              <Button.Label>skip</Button.Label>
            </Button>
            <Button size="sm" variant="secondary" onPress={onSave} isDisabled={isActionDisabled}>
              <Button.Label>save</Button.Label>
            </Button>
            <Button size="sm" variant="primary" onPress={onDone} isDisabled={isActionDisabled}>
              <Button.Label>done</Button.Label>
            </Button>
          </View>

          <Separator className="mx-3 my-2 h-px opacity-100" />

          <View className="items-center px-2 pt-1">
            <Button size="sm" variant="tertiary" onPress={() => router.replace("/(tabs)") }>
              <Button.Label>back to params</Button.Label>
            </Button>
          </View>
        </Menu.Content>
      </Menu.Portal>
    </Menu>
  );
}

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

function AssistantHeader({
  mode,
  guidance,
  onPress,
}: {
  mode: ChallengeMode;
  guidance?: string | null;
  onPress: () => void;
}) {
  if (mode === "solo") {
    return null;
  }

  return (
    <Pressable
      className={cn(
        "border-b border-border px-5 py-3",
        mode === "coach" ? "bg-accent/10" : "bg-surface-secondary",
      )}
      onPress={onPress}
    >
      <Text className="mb-1 text-xs font-medium uppercase tracking-[1.6px] text-muted">
        {mode === "coach" ? "ai coach" : "reveal"}
      </Text>
      <Text className="text-sm leading-6 text-foreground">
        {guidance ??
          (mode === "coach"
            ? "one gentle coaching sentence lives here at a time — tap to ask a clarifying question"
            : "reveal will give one structured answer surface here — tap to inspect and ask follow-ups later")}
      </Text>
    </Pressable>
  );
}

const AUTO_COACH_MIN_NOTES_CHARS = 180;
const AUTO_COACH_MIN_NEW_CHARS = 80;
const AUTO_COACH_IDLE_MS = 2500;
const AUTO_COACH_COOLDOWN_MS = 15000;

function normalizeCoachText(value: string) {
  return value.trim().replace(/\s+/g, " ");
}

export function AnswerScreen() {
  const insets = useSafeAreaInsets();
  const params = useLocalSearchParams<{
    mode?: string;
    challengeId?: string;
  }>();
  const initialMode = useMemo<ChallengeMode>(() => {
    if (
      params.mode === "solo" ||
      params.mode === "coach" ||
      params.mode === "reveal"
    ) {
      return params.mode;
    }

    return "coach";
  }, [params.mode]);

  const [selectedMode, setSelectedMode] = useState<ChallengeMode>(initialMode);
  const [notesDraft, setNotesDraft] = useState("");
  const [conversationSummary, setConversationSummary] = useState("");
  const [, setUpdatedAt] = useState(new Date().toISOString());
  const [isHeaderCollapsed, setHeaderCollapsed] = useState(false);
  const [isAssistantInputOpen, setAssistantInputOpen] = useState(false);
  const [assistantMessage, setAssistantMessage] = useState("");
  const [selectedModelId, setSelectedModelId] = useState<string | undefined>();
  const [availableModels, setAvailableModels] = useState<ModelRecord[]>([]);
  const [challenge, setChallenge] = useState<ChallengeRecord | null>(null);
  const [assistantGuidance, setAssistantGuidance] = useState<string | null>(
    null,
  );
  const [revealAnswer, setRevealAnswer] = useState<string | null>(null);
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
      initialMode,
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
      initialMode,
    });
  }, [initialMode, params, resolvedChallengeId]);

  const resetAnswerState = useCallback(
    (nextMode: ChallengeMode = initialMode) => {
      setChallenge(null);
      setSelectedMode(nextMode);
      setNotesDraft("");
      setConversationSummary("");
      setUpdatedAt(new Date().toISOString());
      setConversationHistory([]);
      setAssistantHistory([]);
      setAssistantGuidance(null);
      setRevealAnswer(null);
      setLastAutoCoachAt(null);
      setLastAutoCoachNotesSnapshot("");
      setAssistantInputOpen(false);
      setAssistantMessage("");
    },
    [initialMode],
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

  const requestCoachGuidance = useCallback(
    async ({
      trigger,
      latestUserRequest,
      appendToHistory = false,
    }: {
      trigger: CoachTriggerReason;
      latestUserRequest?: string;
      appendToHistory?: boolean;
    }) => {
      if (!resolvedChallengeId) {
        return null;
      }

      const result = await generateCoachGuidance(resolvedChallengeId, {
        coachTrigger: trigger,
        latestUserRequest,
      });

      setAssistantGuidance(result.output.guidance);
      setRevealAnswer(null);

      if (appendToHistory) {
        setAssistantHistory((current) => {
          if (current.some((message) => message.text === result.output.guidance)) {
            return current;
          }

          return [
            ...current,
            {
              id: `coach-${Date.now()}`,
              role: "coach",
              text: result.output.guidance,
            },
          ];
        });
      }

      return result;
    },
    [resolvedChallengeId],
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
        setSelectedMode(existingSession.selectedMode ?? initialMode);
        setNotesDraft(existingSession.notesDraft ?? "");
        setConversationSummary(existingSession.conversationSummary ?? "");
        setUpdatedAt(existingSession.updatedAt);
        setConversationHistory(existingSession.conversationHistory);
        setAssistantHistory(
          mapConversationHistoryToChat(existingSession.conversationHistory),
        );
      } else {
        setSelectedMode(initialMode);
        setNotesDraft("");
        setConversationSummary("");
        setUpdatedAt(new Date().toISOString());
        setConversationHistory([]);
        setAssistantHistory([]);
        setAssistantGuidance(null);
        setRevealAnswer(null);
      }

      setChallengeLoading(false);
    }

    void loadScreenState();

    return () => {
      isMounted = false;
    };
  }, [initialMode, resetAnswerState, resolvedChallengeId]);

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
      setAssistantGuidance(null);
      setRevealAnswer(null);
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
        const result = await generateRevealAnswer(resolvedChallengeId!);
        if (!isMounted) {
          return;
        }

        setAssistantGuidance(result.output.guidance);
        setRevealAnswer(result.output.answer);
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

        setAssistantGuidance(
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
  }, [challenge, resolvedChallengeId, selectedMode]);

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
          setAssistantGuidance(
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

  function handleSkip() {
    void (async () => {
      if (!canInteractWithChallenge || !resolvedChallengeId) {
        Alert.alert(
          "no active challenge",
          "Generate or resume a challenge first.",
        );
        return;
      }

      await skipChallenge(resolvedChallengeId);
      resetAnswerState();
      router.replace("/(tabs)");
    })();
  }

  function handleSave() {
    void (async () => {
      if (!canInteractWithChallenge || !resolvedChallengeId) {
        Alert.alert(
          "no active challenge",
          "Generate or resume a challenge first.",
        );
        return;
      }

      await persistSession();
      await markChallengeInProgress(resolvedChallengeId, selectedMode);
      await refreshResolvedChallenge();

      Alert.alert(
        "saved",
        "Your notes are saved. This challenge stays active right where you left it.",
      );
    })();
  }

  function handleDone() {
    void (async () => {
      if (!canInteractWithChallenge || !resolvedChallengeId) {
        Alert.alert(
          "no active challenge",
          "Generate or resume a challenge first.",
        );
        return;
      }

      await persistSession();
      await completeChallenge(resolvedChallengeId);
      resetAnswerState();
      router.replace("/(tabs)");

      void (async () => {
        try {
          await summarizeChallengeSession(resolvedChallengeId);
        } catch (error) {
          console.error("background summary failed", error);
        }
      })();
    })();
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
        onPress={() => {
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

          {selectedMode === "reveal" && revealAnswer ? (
            <View className="rounded-[28px] border border-border bg-surface-secondary px-4 py-4">
              <Text className="mb-2 text-xs font-medium uppercase tracking-[1.4px] text-muted">
                reveal answer
              </Text>
              <Text selectable className="text-sm leading-6 text-foreground">
                {revealAnswer}
              </Text>
            </View>
          ) : null}

          {/* TODO: save-for-later action should persist this session and remove it from the active flow until reopened */}
          </View>
        </KeyboardAwareScrollView>
      </View>

      <Modal
        transparent
        animationType="slide"
        visible={isAssistantInputOpen}
        onRequestClose={() => setAssistantInputOpen(false)}
      >
        <View className="flex-1 justify-end">
          <Pressable
            className="absolute inset-0 bg-black/30"
            onPress={() => setAssistantInputOpen(false)}
          />

          <KeyboardStickyView
            offset={{ closed: 0, opened: 0 }}
            className="rounded-t-[28px] border border-border bg-background"
          >
          <View className="rounded-t-[28px] border border-border bg-background px-5 pb-safe-offset-4 pt-4">
            <View className="mb-3 gap-1">
              <Text className="text-lg font-semibold text-foreground">
                {selectedMode === "reveal"
                  ? "ask about the reveal"
                  : "ask the coach"}
              </Text>
            </View>

            <KeyboardChatScrollView
              className="mb-4"
              style={{ maxHeight: 320 }}
              showsVerticalScrollIndicator={false}
              keyboardLiftBehavior="always"
              offset={insets.bottom}
            >
              <View className="gap-3">
                {assistantHistory.map((message) => (
                  <View
                    key={message.id}
                    className={cn(
                      "w-full",
                      message.role === "coach" ? "items-start" : "items-end",
                    )}
                  >
                    <View
                      className={cn(
                        "rounded-3xl border px-4 py-3",
                        message.role === "coach"
                          ? "border-accent/20 bg-accent/10"
                          : "border-border bg-surface-secondary",
                      )}
                      style={
                        message.role === "coach"
                          ? { marginRight: "15%" }
                          : { marginLeft: "15%" }
                      }
                    >
                      <Text className="mb-1 text-[10px] font-medium uppercase tracking-[1.2px] text-muted">
                        {message.role}
                      </Text>
                      <Text className="text-sm leading-6 text-foreground">
                        {message.text}
                      </Text>
                    </View>
                  </View>
                ))}
              </View>
            </KeyboardChatScrollView>

            <TextField>
              <Label>clarifying question</Label>
              <Input
                multiline
                numberOfLines={4}
                placeholder="Ask a clarifying question about what you are working on..."
                value={assistantMessage}
                onChangeText={(value) => {
                  setAssistantMessage(value);
                  setConversationSummary(value);
                  if (canInteractWithChallenge && resolvedChallengeId) {
                    void persistSession({ conversationSummary: value });
                  }
                }}
                className="min-h-28 items-start py-4"
                textAlignVertical="top"
                isDisabled={!canInteractWithChallenge}
              />
            </TextField>

            <View className="mt-4 flex-row gap-3">
              <Button
                className="flex-1"
                variant="ghost"
                onPress={() => setAssistantInputOpen(false)}
              >
                <Button.Label>close</Button.Label>
              </Button>
              <Button
                className="flex-1"
                variant="primary"
                onPress={() => {
                  void (async () => {
                    const trimmed = assistantMessage.trim();

                    if (!trimmed) {
                      setAssistantInputOpen(false);
                      return;
                    }

                    setAssistantHistory((current) => [
                      ...current,
                      {
                        id: `you-${Date.now()}`,
                        role: "you",
                        text: trimmed,
                      },
                    ]);
                    setAssistantMessage("");
                    setAssistantLoading(true);

                    try {
                      if (selectedMode === "reveal") {
                        if (!canInteractWithChallenge || !resolvedChallengeId) {
                          setAssistantInputOpen(false);
                          return;
                        }

                        const result =
                          await generateRevealAnswer(resolvedChallengeId);
                        setAssistantGuidance(result.output.guidance);
                        setRevealAnswer(result.output.answer);
                        const assistantTurnId = `assistant-${Date.now()}`;
                        const nextHistory: ChallengeConversationTurn[] = [
                          ...conversationHistory,
                          {
                            id: `user-${assistantTurnId}`,
                            role: "user" as const,
                            mode: "reveal" as const,
                            text: trimmed,
                            createdAt: new Date().toISOString(),
                          },
                          {
                            id: assistantTurnId,
                            role: "assistant" as const,
                            mode: "reveal" as const,
                            text: result.output.guidance,
                            answer: result.output.answer,
                            createdAt: new Date().toISOString(),
                          },
                        ];

                        setConversationHistory(nextHistory);
                        setAssistantHistory(
                          mapConversationHistoryToChat(nextHistory),
                        );
                        await persistSession({
                          conversationSummary: trimmed,
                          conversationHistory: nextHistory,
                        });
                      } else {
                        if (!canInteractWithChallenge || !resolvedChallengeId) {
                          setAssistantInputOpen(false);
                          return;
                        }

                        const result = await requestCoachGuidance({
                          trigger: "manual_request",
                          latestUserRequest: trimmed,
                        });

                        if (!result) {
                          return;
                        }

                        const assistantTurnId = `assistant-${Date.now()}`;
                        const nextHistory: ChallengeConversationTurn[] = [
                          ...conversationHistory,
                          {
                            id: `user-${assistantTurnId}`,
                            role: "user" as const,
                            mode: "coach" as const,
                            text: trimmed,
                            createdAt: new Date().toISOString(),
                          },
                          {
                            id: assistantTurnId,
                            role: "assistant" as const,
                            mode: "coach" as const,
                            text: result.output.guidance,
                            createdAt: new Date().toISOString(),
                          },
                        ];

                        setConversationHistory(nextHistory);
                        setAssistantHistory(
                          mapConversationHistoryToChat(nextHistory),
                        );
                        await persistSession({
                          conversationSummary: trimmed,
                          conversationHistory: nextHistory,
                        });
                      }
                    } catch (error) {
                      Alert.alert(
                        "assistant failed",
                        error instanceof Error
                          ? error.message
                          : "Unknown error",
                      );
                    } finally {
                      setAssistantLoading(false);
                      setAssistantInputOpen(false);
                    }
                  })();
                }}
                isDisabled={!canInteractWithChallenge}
              >
                <Button.Label>
                  {isAssistantLoading ? "thinking..." : "send"}
                </Button.Label>
              </Button>
            </View>
          </View>
          </KeyboardStickyView>
        </View>
      </Modal>
    </View>
  );
}
