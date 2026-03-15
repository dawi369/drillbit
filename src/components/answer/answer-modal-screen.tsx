import { Stack, useLocalSearchParams } from "expo-router";
import { Button, Input, Label, TextField } from "heroui-native";
import { useEffect, useMemo, useRef, useState } from "react";
import {
  Keyboard,
  Modal,
  Platform,
  Pressable,
  ScrollView,
  Text,
  View,
} from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import {
  ANSWER_MODAL_MODEL_OPTIONS,
  ANSWER_MODAL_PREVIEW_CHALLENGE,
  ANSWER_MODAL_PREVIEW_COACH_MESSAGES,
} from "@/constants/answer-modal";
import { MODE_OPTIONS } from "@/constants/params";
import { cn } from "@/lib/cn";
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

function ModePicker({
  label,
  selectedMode,
  onSelect,
}: {
  label: string;
  selectedMode: ChallengeMode;
  onSelect: (mode: ChallengeMode) => void;
}) {
  const [isOpen, setIsOpen] = useState(false);
  const selectedOption = MODE_OPTIONS.find(
    (item) => item.value === selectedMode,
  );

  return (
    <>
      <Pressable
        className="w-full rounded-full border border-border bg-surface-secondary px-2 py-0.5"
        onPress={() => setIsOpen(true)}
      >
        <View className="flex-row items-center gap-1.5 overflow-hidden">
          <Text className="text-[9px] font-medium uppercase tracking-[1px] text-muted">
            {label}
          </Text>
          <View className="h-3 w-px bg-border" />
          <Text
            numberOfLines={1}
            ellipsizeMode="tail"
            className="flex-1 text-[10px] font-semibold uppercase tracking-[1px] text-foreground"
          >
            {selectedOption?.label ?? selectedMode}
          </Text>
          <Text className="text-[9px] text-muted">v</Text>
        </View>
      </Pressable>

      <Modal
        transparent
        animationType="fade"
        visible={isOpen}
        onRequestClose={() => setIsOpen(false)}
      >
        <Pressable
          className="flex-1 bg-black/30 px-5 py-16"
          onPress={() => setIsOpen(false)}
        >
          <View className="mt-8 rounded-[28px] border border-border bg-background px-4 py-4">
            <Text className="mb-3 text-sm font-semibold text-foreground">
              choose mode
            </Text>
            <View className="gap-2">
              {MODE_OPTIONS.map((option) => (
                <Pressable
                  key={option.value}
                  className={cn(
                    "rounded-2xl border px-4 py-3",
                    option.value === selectedMode
                      ? "border-accent bg-accent/10"
                      : "border-border bg-surface-secondary",
                  )}
                  onPress={() => {
                    onSelect(option.value);
                    setIsOpen(false);
                  }}
                >
                  <Text
                    className={cn(
                      "mb-1 text-sm font-semibold",
                      option.value === selectedMode
                        ? "text-accent"
                        : "text-foreground",
                    )}
                  >
                    {option.label}
                  </Text>
                  <Text className="text-sm leading-6 text-muted">
                    {option.description}
                  </Text>
                </Pressable>
              ))}
            </View>
          </View>
        </Pressable>
      </Modal>
    </>
  );
}

function ModelPicker({
  selectedModel,
  onSelect,
}: {
  selectedModel: string;
  onSelect: (model: string) => void;
}) {
  const [isOpen, setIsOpen] = useState(false);
  const selectedOption = ANSWER_MODAL_MODEL_OPTIONS.find(
    (option) => option.value === selectedModel,
  );

  return (
    <>
      <Pressable
        className="w-full rounded-full border border-border bg-surface-secondary px-2 py-0.5"
        onPress={() => setIsOpen(true)}
      >
        <View className="flex-row items-center gap-1.5 overflow-hidden">
          <Text className="text-[9px] font-medium uppercase tracking-[1px] text-muted">
            model
          </Text>
          <View className="h-3 w-px bg-border" />
          <Text
            numberOfLines={1}
            ellipsizeMode="tail"
            className="flex-1 text-[10px] font-semibold uppercase tracking-[1px] text-foreground"
          >
            {selectedOption?.value ?? selectedModel}
          </Text>
          <Text className="text-[9px] text-muted">v</Text>
        </View>
      </Pressable>

      <Modal
        transparent
        animationType="fade"
        visible={isOpen}
        onRequestClose={() => setIsOpen(false)}
      >
        <Pressable
          className="flex-1 bg-black/30 px-5 py-16"
          onPress={() => setIsOpen(false)}
        >
          <View className="mt-8 rounded-[28px] border border-border bg-background px-4 py-4">
            <Text className="mb-3 text-sm font-semibold text-foreground">
              choose model
            </Text>
            <View className="gap-2">
              {ANSWER_MODAL_MODEL_OPTIONS.map((option) => (
                <Pressable
                  key={option.value}
                  className={cn(
                    "rounded-2xl border px-4 py-3",
                    option.value === selectedModel
                      ? "border-accent bg-accent/10"
                      : "border-border bg-surface-secondary",
                  )}
                  onPress={() => {
                    onSelect(option.value);
                    setIsOpen(false);
                  }}
                >
                  <Text
                    className={cn(
                      "text-sm font-semibold",
                      option.value === selectedModel
                        ? "text-accent"
                        : "text-foreground",
                    )}
                  >
                    {option.value}
                  </Text>
                  <Text className="mt-1 text-sm leading-6 text-muted">
                    {option.description}
                  </Text>
                </Pressable>
              ))}
            </View>
          </View>
        </Pressable>
      </Modal>
    </>
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
    <Pressable className="items-center py-1" onPress={onPress}>
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
  onPress,
}: {
  mode: ChallengeMode;
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
        {mode === "coach"
          ? "one gentle coaching sentence lives here at a time — tap to ask a clarifying question"
          : "reveal will give one structured answer surface here — tap to inspect and ask follow-ups later"}
      </Text>
    </Pressable>
  );
}

export function AnswerModalScreen() {
  const insets = useSafeAreaInsets();
  const params = useLocalSearchParams<{ mode?: string }>();
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
  const [, setConversationSummary] = useState("");
  const [, setUpdatedAt] = useState(new Date().toISOString());
  const [isHeaderCollapsed, setHeaderCollapsed] = useState(false);
  const [isAssistantInputOpen, setAssistantInputOpen] = useState(false);
  const [assistantMessage, setAssistantMessage] = useState("");
  const [isKeyboardVisible, setKeyboardVisible] = useState(false);
  const [keyboardHeight, setKeyboardHeight] = useState(0);
  const [selectedModel, setSelectedModel] = useState<string>(
    ANSWER_MODAL_MODEL_OPTIONS[0].value,
  );
  const assistantHistoryRef = useRef<ScrollView | null>(null);

  function updateTimestamp() {
    setUpdatedAt(new Date().toISOString());
  }

  useEffect(() => {
    const showEvent =
      Platform.OS === "ios" ? "keyboardWillShow" : "keyboardDidShow";
    const hideEvent =
      Platform.OS === "ios" ? "keyboardWillHide" : "keyboardDidHide";

    const showSubscription = Keyboard.addListener(showEvent, (event) => {
      setKeyboardVisible(true);
      setKeyboardHeight(event.endCoordinates.height);
    });

    const hideSubscription = Keyboard.addListener(hideEvent, () => {
      setKeyboardVisible(false);
      setKeyboardHeight(0);
    });

    return () => {
      showSubscription.remove();
      hideSubscription.remove();
    };
  }, []);

  useEffect(() => {
    if (!isAssistantInputOpen) {
      return;
    }

    const timer = setTimeout(() => {
      assistantHistoryRef.current?.scrollToEnd({ animated: false });
    }, 0);

    return () => clearTimeout(timer);
  }, [isAssistantInputOpen]);

  return (
    <>
      <Stack.Screen
        options={{
          title: "answer",
          presentation: "modal",
          headerShown: false,
        }}
      />

      <View className="flex-1 bg-background">
        <View
          className="border-b border-border bg-background px-5"
          style={{ paddingTop: insets.top }}
        >
          {!isHeaderCollapsed ? (
            <View className="gap-1 pb-1">
              <View className="gap-1">
                <Text className="text-lg font-semibold tracking-tight text-foreground">
                  {ANSWER_MODAL_PREVIEW_CHALLENGE.title}
                </Text>
                <ScrollView
                  style={{ maxHeight: 120 }}
                  showsVerticalScrollIndicator={false}
                >
                  <Text className="pr-2 text-sm leading-5 text-muted">
                    {ANSWER_MODAL_PREVIEW_CHALLENGE.teaser}
                  </Text>
                </ScrollView>
              </View>
            </View>
          ) : (
            <View className="pb-1" />
          )}

          {!isHeaderCollapsed ? (
            <View className="items-center pb-1 pt-0.5">
              <View className="flex-row justify-center gap-2">
                <MetaPill label={ANSWER_MODAL_PREVIEW_CHALLENGE.topic} />
                <MetaPill label={ANSWER_MODAL_PREVIEW_CHALLENGE.difficulty} />
              </View>
            </View>
          ) : null}

          <View className="flex-row items-center gap-2 pb-1">
            <View className="min-w-0 flex-1 items-start">
              <ModelPicker
                selectedModel={selectedModel}
                onSelect={(model) => setSelectedModel(model)}
              />
            </View>

            <View className="shrink-0 items-center px-1">
              <HeaderToggle
                collapsed={isHeaderCollapsed}
                onPress={() => setHeaderCollapsed((current) => !current)}
              />
            </View>

            <View className="min-w-0 flex-1 items-end">
              <ModePicker
                label="mode"
                selectedMode={selectedMode}
                onSelect={(mode) => {
                  setSelectedMode(mode);
                  updateTimestamp();
                }}
              />
            </View>
          </View>
        </View>

        <AssistantHeader
          mode={selectedMode}
          onPress={() => {
            setAssistantInputOpen(true);
          }}
        />

        <View
          className={cn(
            "flex-1 px-5 pt-4",
            isKeyboardVisible ? "pb-0" : "pb-safe-offset-4",
          )}
          style={
            isKeyboardVisible
              ? { marginBottom: Math.max(keyboardHeight + 10, 0) }
              : undefined
          }
        >
          <View className="flex-1 gap-4">
            <TextField className="flex-1">
              <View className="mb-1 mt-[-4px] flex-row items-center justify-between gap-3 px-1">
                <Pressable
                  className="flex-1 flex-row items-center"
                  onPress={() => Keyboard.dismiss()}
                >
                  <Label>answer</Label>
                  <View className="flex-1" />
                </Pressable>
                <View className="flex-row items-center gap-2">
                  <Button size="sm" variant="ghost">
                    <Button.Label>skip</Button.Label>
                  </Button>
                  <Button size="sm" variant="secondary">
                    <Button.Label>save</Button.Label>
                  </Button>
                  <Button size="sm" variant="primary">
                    <Button.Label>done</Button.Label>
                  </Button>
                </View>
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
                  updateTimestamp();
                }}
                scrollEnabled
                className="flex-1 items-start rounded-[28px] border border-border bg-surface px-4 py-4"
                textAlignVertical="top"
              />
            </TextField>

            {/* TODO: wire selectedMode, notesDraft, conversationSummary, updatedAt to ChallengeSessionRecord persistence */}
            {/* TODO: trigger coach inference only after meaningful note changes and under a cooldown instead of constant polling */}
            {/* TODO: save-for-later action should persist this session and remove it from the active flow until reopened */}
          </View>
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

            <View className="rounded-t-[28px] border border-border bg-background px-5 pb-safe-offset-4 pt-4">
              <View className="mb-3 gap-1">
                <Text className="text-lg font-semibold text-foreground">
                  ask the coach
                </Text>
              </View>

              <ScrollView
                ref={assistantHistoryRef}
                className="mb-4"
                style={{ maxHeight: 320 }}
                showsVerticalScrollIndicator={false}
                onContentSizeChange={() => {
                  if (isAssistantInputOpen) {
                    assistantHistoryRef.current?.scrollToEnd({ animated: false });
                  }
                }}
              >
               <View className="gap-3">
                  {ANSWER_MODAL_PREVIEW_COACH_MESSAGES.map((message) => (
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
              </ScrollView>

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
                    updateTimestamp();
                  }}
                  className="min-h-28 items-start py-4"
                  textAlignVertical="top"
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
                  onPress={() => setAssistantInputOpen(false)}
                >
                  <Button.Label>send later</Button.Label>
                </Button>
              </View>
            </View>
          </View>
        </Modal>
      </View>
    </>
  );
}
