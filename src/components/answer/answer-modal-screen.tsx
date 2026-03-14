import { Stack, useLocalSearchParams } from "expo-router";
import { Button, Card, Input, Label, TextField } from "heroui-native";
import { useMemo, useState } from "react";
import { KeyboardAvoidingView, Modal, Pressable, Text, View } from "react-native";

import { MODE_OPTIONS } from "@/constants/params";
import {
  ANSWER_MODAL_MODE_COPY,
  ANSWER_MODAL_PREVIEW_CHALLENGE,
} from "@/constants/answer-modal";
import { cn } from "@/lib/cn";
import type { ChallengeMode } from "@/lib/widgets/types";

function MetaPill({ label }: { label: string }) {
  return (
    <View className="rounded-full border border-border bg-surface-secondary px-2.5 py-1">
      <Text className="text-[11px] font-medium uppercase tracking-[1.2px] text-foreground">
        {label}
      </Text>
    </View>
  );
}

function ModePicker({
  selectedMode,
  onSelect,
}: {
  selectedMode: ChallengeMode;
  onSelect: (mode: ChallengeMode) => void;
}) {
  const [isOpen, setIsOpen] = useState(false);
  const selectedOption = MODE_OPTIONS.find((item) => item.value === selectedMode);

  return (
    <>
      <Pressable
        className="rounded-full border border-accent/20 bg-accent/10 px-2.5 py-1"
        onPress={() => setIsOpen(true)}
      >
        <View className="flex-row items-center gap-1.5">
          <Text className="text-[11px] font-medium uppercase tracking-[1.2px] text-accent">
            {selectedOption?.label ?? selectedMode}
          </Text>
          <Text className="text-[10px] text-accent">v</Text>
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
            <Text className="mb-3 text-sm font-semibold text-foreground">choose mode</Text>
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
                      option.value === selectedMode ? "text-accent" : "text-foreground",
                    )}
                  >
                    {option.label}
                  </Text>
                  <Text className="text-sm leading-6 text-muted">{option.description}</Text>
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
        <View className="h-4 w-20 items-center justify-center">
          <View className="relative h-3 w-16">
            <View
              className={cn(
                "absolute left-1 top-1 h-[2px] w-7 rounded-full bg-border",
                collapsed ? "rotate-[12deg]" : "-rotate-[12deg]",
              )}
            />
            <View
              className={cn(
                "absolute right-1 top-1 h-[2px] w-7 rounded-full bg-border",
                collapsed ? "-rotate-[12deg]" : "rotate-[12deg]",
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

  const modeCopy = ANSWER_MODAL_MODE_COPY[selectedMode];

  function updateTimestamp() {
    setUpdatedAt(new Date().toISOString());
  }

    return (
    <>
      <Stack.Screen
        options={{
          title: "answer",
          presentation: "modal",
          headerShown: false,
        }}
      />

      <KeyboardAvoidingView className="flex-1 bg-background" behavior="padding">
        <View className="border-b border-border bg-background px-5 pt-safe-offset-4">
          {!isHeaderCollapsed ? (
            <View className="gap-2 pb-1">
              <View className="gap-1">
                <Text className="text-lg font-semibold tracking-tight text-foreground">
                  {ANSWER_MODAL_PREVIEW_CHALLENGE.title}
                </Text>
                <Text className="text-sm leading-5 text-muted">
                  {ANSWER_MODAL_PREVIEW_CHALLENGE.teaser}
                </Text>
              </View>

              <View className="flex-row flex-wrap items-center gap-2">
                <MetaPill label={ANSWER_MODAL_PREVIEW_CHALLENGE.topic} />
                <MetaPill label={ANSWER_MODAL_PREVIEW_CHALLENGE.difficulty} />
                <ModePicker
                  selectedMode={selectedMode}
                  onSelect={(mode) => {
                    setSelectedMode(mode);
                    updateTimestamp();
                  }}
                />
              </View>
            </View>
          ) : (
            <View className="flex-row flex-wrap items-center gap-2 pb-1">
              <MetaPill label={ANSWER_MODAL_PREVIEW_CHALLENGE.topic} />
              <MetaPill label={ANSWER_MODAL_PREVIEW_CHALLENGE.difficulty} />
              <ModePicker
                selectedMode={selectedMode}
                onSelect={(mode) => {
                  setSelectedMode(mode);
                  updateTimestamp();
                }}
              />
            </View>
          )}

          <HeaderToggle
            collapsed={isHeaderCollapsed}
            onPress={() => setHeaderCollapsed((current) => !current)}
          />
        </View>

        <AssistantHeader
          mode={selectedMode}
          onPress={() => {
            setAssistantInputOpen(true);
          }}
        />

        <View className="flex-1 px-5 pb-safe-offset-4 pt-4">
          <View className="flex-1 gap-4">
            <Card className="flex-1 rounded-[28px] border border-border bg-surface">
              <Card.Body className="gap-4">
                <View className="gap-2">
                  <Card.Title className="text-xl text-foreground">notes canvas</Card.Title>
                  <Card.Description className="text-sm leading-6 text-muted">
                    The primary solving surface. Keep this central in every mode for outlines, trade-offs, and rough diagrams.
                  </Card.Description>
                </View>

                <TextField className="flex-1">
                  <Label>working notes</Label>
                  <Input
                    multiline
                    numberOfLines={10}
                    placeholder="Sketch components, trade-offs, bottlenecks, and edge cases here..."
                    value={notesDraft}
                    onChangeText={(value) => {
                      setNotesDraft(value);
                      updateTimestamp();
                    }}
                    className="min-h-48 flex-1 items-start py-4"
                    textAlignVertical="top"
                  />
                </TextField>
              </Card.Body>
            </Card>

            <Card className="min-h-40 rounded-[28px] border border-border bg-surface">
              <Card.Body className="gap-4">
                <View className="gap-1.5">
                  <Card.Title className="text-xl text-foreground">{modeCopy.title}</Card.Title>
                  <Card.Description className="text-sm leading-6 text-muted">
                    {modeCopy.body}
                  </Card.Description>
                </View>

                <View
                  className={cn(
                    "rounded-3xl border px-4 py-4",
                    selectedMode === "solo"
                      ? "border-border bg-surface-secondary"
                      : "border-accent/20 bg-accent/10",
                  )}
                >
                  <Text className="text-sm leading-6 text-foreground">
                    {selectedMode === "solo"
                      ? "solo stays intentionally quiet. The answer area above remains the full solving surface without AI interruption."
                      : selectedMode === "coach"
                        ? "coach responses will appear here as a guided interview thread with probes, hinting, and trade-off pressure."
                        : "reveal content will appear here as a structured answer surface instead of a traditional chat thread."}
                  </Text>
                </View>

                {/* TODO: wire selectedMode, notesDraft, conversationSummary, updatedAt to ChallengeSessionRecord persistence */}
                {/* TODO: trigger coach inference only after meaningful note changes and under a cooldown instead of constant polling */}
                {/* TODO: save-for-later action should persist this session and remove it from the active flow until reopened */}
              </Card.Body>
            </Card>
          </View>

          <View className="border-t border-border bg-background pt-3">
            <View className="flex-row gap-3">
              <Button className="flex-1" variant="ghost">
                <Button.Label>skip</Button.Label>
              </Button>
              <Button className="flex-1" variant="secondary">
                <Button.Label>save</Button.Label>
              </Button>
              <Button className="flex-[2]" variant="primary">
                <Button.Label>done</Button.Label>
              </Button>
            </View>
          </View>
        </View>

        <Modal
          transparent
          animationType="slide"
          visible={isAssistantInputOpen}
          onRequestClose={() => setAssistantInputOpen(false)}
        >
          <Pressable className="flex-1 bg-black/30" onPress={() => setAssistantInputOpen(false)}>
            <Pressable className="mt-auto rounded-t-[28px] border border-border bg-background px-5 pb-safe-offset-4 pt-4">
              <View className="mb-3 gap-1">
                <Text className="text-lg font-semibold text-foreground">ask the ai</Text>
                <Text className="text-sm leading-6 text-muted">
                  This prompt stays separate from the main answer canvas so the user keeps full control of the working area.
                </Text>
              </View>

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
                <Button className="flex-1" variant="ghost" onPress={() => setAssistantInputOpen(false)}>
                  <Button.Label>close</Button.Label>
                </Button>
                <Button className="flex-1" variant="primary" onPress={() => setAssistantInputOpen(false)}>
                  <Button.Label>send later</Button.Label>
                </Button>
              </View>
            </Pressable>
          </Pressable>
        </Modal>
      </KeyboardAvoidingView>
    </>
  );
}
