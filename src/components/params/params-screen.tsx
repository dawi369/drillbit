import DateTimePicker from "@react-native-community/datetimepicker";
import { Button, Separator } from "heroui-native";
import { useEffect, useMemo, useState } from "react";
import { Modal, Pressable, ScrollView, Text, TextInput, View } from "react-native";

import {
  CADENCE_OPTIONS,
  DIFFICULTY_OPTIONS,
  MODE_OPTIONS,
} from "@/constants/params";
import { cn } from "@/lib/cn";
import { getFocusPromptPresets } from "@/lib/prompts/prompt-library";
import {
  createDefaultSettings,
  ensureDefaultModels,
  ensureDefaultSettings,
  listModels,
  normalizeChallengeCadenceHours,
  normalizeFirstChallengeTimeMinutes,
  refreshReadyChallengeExpirations,
  upsertSettings,
} from "@/lib/storage/repository";
import type { ModelRecord, UserSettingsRecord } from "@/lib/storage/types";
import {
  dateToTimeMinutes,
  formatTimeMinutes,
  timeMinutesToDate,
} from "@/lib/time";

import { OptionChip } from "./option-chip";

function Section({
  title,
  description,
  children,
}: {
  title: string;
  description?: string;
  children: React.ReactNode;
}) {
  return (
    <View className="gap-4">
      <View className="gap-1 px-1">
        <Text className="text-xl font-semibold tracking-tight text-foreground">
          {title}
        </Text>
        {description ? (
          <Text className="text-sm leading-6 text-muted">{description}</Text>
        ) : null}
      </View>
      {children}
    </View>
  );
}

function SectionBody({ children }: { children: React.ReactNode }) {
  return <View className="gap-0 border-t border-border/40 pt-2">{children}</View>;
}

function PageHeader() {
  return (
    <View className="gap-3">
      <Text className="text-[40px] font-semibold tracking-tight text-foreground">
        params
      </Text>
      <Text className="max-w-xl text-[15px] leading-6 text-muted">
        Tune the practice brief, default help level, model, and schedule for new
        challenges.
      </Text>
    </View>
  );
}

function Row({
  title,
  description,
  value,
  children,
  valueSelectable = false,
}: {
  title: string;
  description?: string;
  value?: string;
  children?: React.ReactNode;
  valueSelectable?: boolean;
}) {
  return (
    <View className="gap-2.5 py-5">
      <View className="gap-1">
        <Text className="text-[15px] font-semibold text-foreground">{title}</Text>
        {description ? (
          <Text className="text-sm leading-6 text-muted">{description}</Text>
        ) : null}
      </View>

      {value ? (
        <Text
          selectable={valueSelectable}
          className="text-sm leading-6 text-foreground"
        >
          {value}
        </Text>
      ) : null}

      {children}
    </View>
  );
}

function PickerRow({
  title,
  description,
  value,
  onPress,
}: {
  title: string;
  description: string;
  value: string;
  onPress: () => void;
}) {
  return (
    <Pressable
      className="rounded-[22px] px-3 py-3 active:bg-surface-secondary/35"
      onPress={onPress}
    >
      <View className="flex-row items-start justify-between gap-3">
        <View className="min-w-0 flex-1 gap-1">
          <Text className="text-[15px] font-semibold text-foreground">{title}</Text>
          <Text className="text-sm leading-6 text-muted">{description}</Text>
        </View>

        <View className="max-w-[46%] items-end gap-1 pt-0.5">
          <Text numberOfLines={2} className="text-sm font-medium text-foreground">
            {value}
          </Text>
          <Text className="text-xs font-medium uppercase tracking-[1.4px] text-muted">
            choose
          </Text>
        </View>
      </View>
    </Pressable>
  );
}

function SelectableRow({
  title,
  description,
  selected,
  onPress,
}: {
  title: string;
  description: string;
  selected: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable
      className={cn(
        "flex-row items-start gap-3 rounded-[22px] px-3 py-3",
        selected ? "bg-accent/10" : "bg-transparent active:bg-surface-secondary/40",
      )}
      onPress={onPress}
    >
      <View
        className={cn(
          "mt-1 h-2.5 w-2.5 rounded-full",
          selected ? "bg-accent" : "bg-border",
        )}
      />
      <View className="min-w-0 flex-1 gap-1">
        <View className="flex-row items-start justify-between gap-3">
          <Text
            className={cn(
              "flex-1 text-base font-semibold",
              selected ? "text-accent" : "text-foreground",
            )}
          >
            {title}
          </Text>
          {selected ? (
            <Text className="text-[11px] font-semibold uppercase tracking-[1.4px] text-accent">
              selected
            </Text>
          ) : null}
        </View>

        <Text className="text-sm leading-6 text-muted">{description}</Text>
      </View>
    </Pressable>
  );
}

function FocusPresetChip({
  label,
  selected,
  onPress,
}: {
  label: string;
  selected: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable
      className={cn(
        "rounded-full border px-4 py-2.5",
        selected
          ? "border-accent bg-accent/10"
          : "border-border/60 bg-transparent active:bg-surface-secondary/35",
      )}
      onPress={onPress}
    >
      <Text
        className={cn(
          "text-sm font-semibold",
          selected ? "text-accent" : "text-foreground",
        )}
      >
        {label}
      </Text>
    </Pressable>
  );
}

function ModelPickerSheet({
  visible,
  models,
  selectedModelId,
  onClose,
  onSelect,
}: {
  visible: boolean;
  models: ModelRecord[];
  selectedModelId?: string;
  onClose: () => void;
  onSelect: (modelId: string) => void;
}) {
  return (
    <Modal
      transparent
      animationType="fade"
      visible={visible}
      onRequestClose={onClose}
    >
      <View className="flex-1 justify-end bg-black/28">
        <Pressable className="flex-1" onPress={onClose} />

        <View className="rounded-t-[32px] border border-border/60 bg-background px-5 pb-safe-offset-6 pt-3">
          <View className="mb-4 self-center h-1.5 w-12 rounded-full bg-border/80" />

          <View className="mb-4 flex-row items-start justify-between gap-3">
            <View className="min-w-0 flex-1 gap-1">
              <Text className="text-xl font-semibold tracking-tight text-foreground">
                choose model
              </Text>
              <Text className="text-sm leading-6 text-muted">
                Pick the model drillbit should use for generation and in-screen help.
              </Text>
            </View>

            <Pressable onPress={onClose}>
              <Text className="text-sm font-medium text-muted">done</Text>
            </Pressable>
          </View>

          <ScrollView
            showsVerticalScrollIndicator={false}
            contentContainerClassName="gap-2 pb-2"
          >
            {models.map((model) => {
              const isSelected = model.id === selectedModelId;

              return (
                <Pressable
                  key={model.id}
                  className={cn(
                    "rounded-[24px] px-4 py-4",
                    isSelected ? "bg-accent/10" : "bg-surface-secondary/24",
                  )}
                  onPress={() => {
                    onSelect(model.id);
                    onClose();
                  }}
                >
                  <View className="flex-row items-start justify-between gap-3">
                    <View className="min-w-0 flex-1 gap-1">
                      <Text
                        className={cn(
                          "text-base font-semibold",
                          isSelected ? "text-accent" : "text-foreground",
                        )}
                      >
                        {model.label}
                      </Text>
                      <Text selectable className="text-sm leading-6 text-muted">
                        {model.remoteId}
                      </Text>
                    </View>

                    {isSelected ? (
                      <Text className="pt-0.5 text-xs font-semibold uppercase tracking-[1.4px] text-accent">
                        selected
                      </Text>
                    ) : null}
                  </View>
                </Pressable>
              );
            })}

            {models.length === 0 ? (
              <Text className="py-4 text-sm text-muted">no models available</Text>
            ) : null}
          </ScrollView>
        </View>
      </View>
    </Modal>
  );
}

function normalizeFocusPrompt(value: string) {
  return value.trim().replace(/\s+/g, " ");
}

export function ParamsScreen() {
  const initialDraft = useMemo(() => createDefaultSettings(), []);
  const focusPromptPresets = useMemo(() => getFocusPromptPresets(), []);
  const [draft, setDraft] = useState<UserSettingsRecord>(initialDraft);
  const [savedSettings, setSavedSettings] =
    useState<UserSettingsRecord>(initialDraft);
  const [isTimePickerVisible, setTimePickerVisible] = useState(false);
  const [isModelPickerVisible, setModelPickerVisible] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [saveStatus, setSaveStatus] = useState<string | null>(null);
  const [models, setModels] = useState<ModelRecord[]>([]);

  const firstChallengeTime =
    draft.firstChallengeTimeMinutes ??
    initialDraft.firstChallengeTimeMinutes ??
    0;
  const focusPromptCharacterCount = draft.focusPrompt.trim().length;
  const activeFocusPreset =
    focusPromptPresets.find(
      (preset) =>
        normalizeFocusPrompt(preset.prompt) ===
        normalizeFocusPrompt(draft.focusPrompt),
    ) ?? null;
  const selectedModel =
    models.find((model) => model.id === draft.selectedModelId) ?? null;

  const hasUnsavedChanges =
    draft.focusPrompt !== savedSettings.focusPrompt ||
    draft.preferredDifficulty !== savedSettings.preferredDifficulty ||
    draft.preferredMode !== savedSettings.preferredMode ||
    draft.selectedModelId !== savedSettings.selectedModelId ||
    draft.challengeCadenceHours !== savedSettings.challengeCadenceHours ||
    draft.firstChallengeTimeMinutes !== savedSettings.firstChallengeTimeMinutes;

  const footerStatus = isSaving
    ? "saving..."
    : hasUnsavedChanges
      ? "unsaved changes"
      : saveStatus ?? "all changes saved";

  useEffect(() => {
    let isMounted = true;

    async function loadSettings() {
      await ensureDefaultModels();
      const [settings, storedModels] = await Promise.all([
        ensureDefaultSettings(),
        listModels({ includeDisabled: true }),
      ]);

      if (!isMounted) {
        return;
      }

      setDraft(settings);
      setSavedSettings(settings);
      setModels(storedModels);
      setIsLoading(false);
    }

    void loadSettings();

    return () => {
      isMounted = false;
    };
  }, []);

  async function handleSaveSettings() {
    setIsSaving(true);
    setSaveStatus(null);

    try {
      const nextSettings: UserSettingsRecord = {
        ...draft,
        challengeCadenceHours: normalizeChallengeCadenceHours(
          draft.challengeCadenceHours ?? initialDraft.challengeCadenceHours ?? 24,
        ),
        firstChallengeTimeMinutes: normalizeFirstChallengeTimeMinutes(
          draft.firstChallengeTimeMinutes ??
            initialDraft.firstChallengeTimeMinutes ??
            0,
        ),
        updatedAt: new Date().toISOString(),
      };

      await upsertSettings(nextSettings);
      await refreshReadyChallengeExpirations(nextSettings);
      setDraft(nextSettings);
      setSavedSettings(nextSettings);
      setSaveStatus("saved locally");
    } catch (error) {
      setSaveStatus(
        error instanceof Error ? error.message : "failed to save settings",
      );
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <View className="flex-1 bg-background">
      <ScrollView
        className="flex-1"
        contentInsetAdjustmentBehavior="automatic"
        contentContainerClassName="gap-12 px-5 pb-safe-offset-10 pt-safe-offset-7"
      >
        <PageHeader />

        {isLoading ? (
          <Text className="text-sm text-muted">loading saved settings...</Text>
        ) : null}

        <View className="gap-5">
          <View className="gap-1.5">
            <Text className="text-[22px] font-semibold tracking-tight text-foreground">
              focus
            </Text>
            <Text className="text-sm leading-6 text-muted">
              This brief steers every fresh challenge. Make it specific enough to
              feel consistent from session to session.
            </Text>
          </View>

          <ScrollView
            horizontal
            showsHorizontalScrollIndicator={false}
            contentContainerClassName="gap-2.5 pr-2"
          >
            {focusPromptPresets.map((preset) => (
              <FocusPresetChip
                key={preset.id}
                label={preset.title}
                selected={activeFocusPreset?.id === preset.id}
                onPress={() =>
                  setDraft((current) => ({ ...current, focusPrompt: preset.prompt }))
                }
              />
            ))}
          </ScrollView>

          <Text className="text-sm leading-6 text-muted">
            {activeFocusPreset?.description ??
              "Include the interview lane, target domains, trade-offs to probe, and prompt shapes to avoid."}
          </Text>

          <View className="overflow-hidden rounded-[30px] border border-border/35 bg-surface-secondary/18 px-5 py-5">
            <View className="mb-3 flex-row items-start justify-between gap-3 border-b border-border/35 pb-3">
              <View className="min-w-0 flex-1 gap-1">
                <Text className="text-xs font-semibold uppercase tracking-[1.4px] text-muted">
                  focus prompt
                </Text>
                <Text className="text-sm font-medium text-foreground">
                  {activeFocusPreset?.title ?? "custom brief"}
                </Text>
              </View>

              <View className="items-end gap-1">
                <Text className="text-xs font-medium uppercase tracking-[1.4px] text-muted">
                  {focusPromptCharacterCount > 0
                    ? `${focusPromptCharacterCount} chars`
                    : "set this before generating"}
                </Text>
                {draft.focusPrompt.length > 0 ? (
                  <Pressable
                    onPress={() =>
                      setDraft((current) => ({ ...current, focusPrompt: "" }))
                    }
                  >
                    <Text className="text-sm font-medium text-muted">clear</Text>
                  </Pressable>
                ) : null}
              </View>
            </View>

            <TextInput
              multiline
              textAlignVertical="top"
              placeholder="Example: Senior system design interviews for collaboration and platform products. Push on service boundaries, write amplification, consistency trade-offs, and rollout safety. Avoid toy CRUD prompts and trivia-only questions."
              value={draft.focusPrompt}
              onChangeText={(value) =>
                setDraft((current) => ({ ...current, focusPrompt: value }))
              }
              className="h-64 text-base leading-7 text-foreground"
              placeholderTextColorClassName="accent-muted"
            />
          </View>

          {focusPromptCharacterCount === 0 ? (
            <Text className="text-sm leading-6 text-muted">
              Do not leave this empty. Start from one of the briefs above or write
              your own before generating challenges.
            </Text>
          ) : focusPromptCharacterCount < 120 ? (
            <Text className="text-sm leading-6 text-muted">
              Good start. Add a little more detail about scope, difficulty, or
              what to avoid so results stay consistent.
            </Text>
          ) : null}
        </View>

        <Section
          title="defaults"
          description="How new challenges should open before you start working."
        >
          <SectionBody>
            <Row title="difficulty" description="Target level for newly generated prompts.">
              <View className="flex-row flex-wrap gap-2 pt-1">
                {DIFFICULTY_OPTIONS.map((option) => (
                  <OptionChip
                    key={option.value}
                    label={option.label}
                    selected={draft.preferredDifficulty === option.value}
                    onPress={() =>
                      setDraft((current) => ({
                        ...current,
                        preferredDifficulty: option.value,
                      }))
                    }
                  />
                ))}
              </View>
            </Row>

            <Separator className="opacity-60" />

            <Row title="mode" description="Default help level when you enter a challenge.">
              <View className="gap-1 pt-1">
                {MODE_OPTIONS.map((option) => (
                  <SelectableRow
                    key={option.value}
                    title={option.label}
                    description={option.description}
                    selected={draft.preferredMode === option.value}
                    onPress={() =>
                      setDraft((current) => ({
                        ...current,
                        preferredMode: option.value,
                      }))
                    }
                  />
                ))}
              </View>
            </Row>

            <Separator className="opacity-60" />

            <Row title="model" description="Choose the model used across generation and help.">
              <PickerRow
                title="selected model"
                description={selectedModel?.remoteId ?? "No model selected yet."}
                value={selectedModel?.label ?? "choose model"}
                onPress={() => setModelPickerVisible(true)}
              />
            </Row>
          </SectionBody>
        </Section>

        <Section
          title="schedule"
          description="When the next ready challenge becomes the one that matters."
        >
          <SectionBody>
            <Row
              title="first challenge time"
              description="Daily starting point for the schedule."
              value={formatTimeMinutes(firstChallengeTime)}
            >
              <Button
                variant="secondary"
                onPress={() => setTimePickerVisible((current) => !current)}
              >
                <Button.Label>
                  {isTimePickerVisible ? "hide time picker" : "edit time"}
                </Button.Label>
              </Button>

              {isTimePickerVisible ? (
                <View className="rounded-[20px] bg-surface-secondary/35 px-2 py-2">
                  <DateTimePicker
                    value={timeMinutesToDate(firstChallengeTime)}
                    mode="time"
                    minuteInterval={15}
                    onChange={(_, nextValue) => {
                      if (!nextValue) {
                        return;
                      }

                      setDraft((current) => ({
                        ...current,
                        firstChallengeTimeMinutes: dateToTimeMinutes(nextValue),
                      }));
                    }}
                  />
                </View>
              ) : null}
            </Row>

            <Separator className="opacity-60" />

            <Row title="cadence" description="How often a fresh challenge should rotate in.">
              <View className="flex-row flex-wrap gap-2 pt-1">
                {CADENCE_OPTIONS.map((option) => (
                  <OptionChip
                    key={option.value}
                    label={option.label}
                    selected={draft.challengeCadenceHours === option.value}
                    onPress={() =>
                      setDraft((current) => ({
                        ...current,
                        challengeCadenceHours: option.value,
                      }))
                    }
                  />
                ))}
              </View>
            </Row>
          </SectionBody>
        </Section>

        <Section
          title="save"
          description="Save changes when you are happy with them, or revert to the last saved settings."
        >
          <SectionBody>
            <Row title="settings state" description={footerStatus}>
              <View className="flex-row gap-3 pt-1">
                <Button
                  className="flex-1"
                  variant="secondary"
                  onPress={() => {
                    setDraft(savedSettings);
                    setTimePickerVisible(false);
                    setSaveStatus(null);
                  }}
                >
                  <Button.Label>revert</Button.Label>
                </Button>
                <Button
                  className="flex-1"
                  variant="primary"
                  isDisabled={isSaving || !hasUnsavedChanges}
                  onPress={() => {
                    void handleSaveSettings();
                  }}
                >
                  <Button.Label>{isSaving ? "saving..." : "save"}</Button.Label>
                </Button>
              </View>
            </Row>
          </SectionBody>
        </Section>
      </ScrollView>

      <ModelPickerSheet
        visible={isModelPickerVisible}
        models={models}
        selectedModelId={draft.selectedModelId}
        onClose={() => setModelPickerVisible(false)}
        onSelect={(modelId) => {
          setDraft((current) => ({ ...current, selectedModelId: modelId }));
        }}
      />
    </View>
  );
}
