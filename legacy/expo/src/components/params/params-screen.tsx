import { Button, Dialog, Select, Separator } from "heroui-native";
import type { ComponentProps } from "react";
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  Pressable,
  ScrollView,
  Text,
  TextInput,
  View,
  Platform,
} from "react-native";

import {
  CADENCE_OPTIONS,
  DIFFICULTY_OPTIONS,
  MODE_OPTIONS,
} from "@/constants/params";
import { cn } from "@/lib/cn";
import { syncChallengeNotifications } from "@/lib/notifications";
import { subscribeToModelsRefresh } from "@/lib/models-refresh";
import { getFocusPromptPresets } from "@/lib/prompts/prompt-library";
import { subscribeToSettingsRefresh } from "@/lib/settings-refresh";
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
import type {
  ChallengeCadenceHours,
  ModelRecord,
  UserSettingsRecord,
} from "@/lib/storage/types";
import {
  dateToTimeMinutes,
  formatTimeMinutes,
  timeMinutesToDate,
} from "@/lib/time";

import { OptionChip } from "./option-chip";

type DateTimePickerProps = ComponentProps<
  typeof import("@react-native-community/datetimepicker").default
>;

function NativeTimePicker(props: DateTimePickerProps) {
  const [DateTimePicker, setDateTimePicker] = useState<
    typeof import("@react-native-community/datetimepicker").default | null
  >(null);

  useEffect(() => {
    if (Platform.OS === "web") {
      return;
    }

    let isMounted = true;

    void import("@react-native-community/datetimepicker").then((module) => {
      if (isMounted) {
        setDateTimePicker(() => module.default);
      }
    });

    return () => {
      isMounted = false;
    };
  }, []);

  if (Platform.OS === "web" || !DateTimePicker) {
    return null;
  }

  return <DateTimePicker {...props} />;
}

function PanelIntro({
  title,
  description,
}: {
  title: string;
  description: string;
}) {
  return (
    <View className="gap-1 px-1 pb-3">
      <Text className="text-2xl font-semibold text-foreground">
        {title}
      </Text>
      <Text className="text-sm leading-6 text-muted">{description}</Text>
    </View>
  );
}

function PageHeader() {
  return (
    <View className="gap-3">
      <Text className="text-3xl font-semibold text-foreground">
        Practice setup
      </Text>
      <Text className="max-w-xl text-base leading-6 text-muted">
        Tune your focus prompt, default help level, model, and schedule for new
        challenges.
      </Text>
    </View>
  );
}

function SkeletonLine({ className }: { className: string }) {
  return (
    <View
      className={cn(
        "overflow-hidden rounded-full bg-surface-secondary/70",
        className,
      )}
    />
  );
}

function LoadingSettingsSkeleton() {
  return (
    <View className="gap-5 rounded-[var(--radius)] border border-border/45 bg-surface-secondary/10 px-5 py-5">
      <View className="gap-3">
        <SkeletonLine className="h-4 w-28" />
        <SkeletonLine className="h-7 w-44" />
        <SkeletonLine className="h-4 w-full" />
        <SkeletonLine className="h-4 w-4/5" />
      </View>

      <View className="gap-3">
        <SkeletonLine className="h-10 w-full rounded-[var(--radius)]" />
        <SkeletonLine className="h-10 w-full rounded-[var(--radius)]" />
        <SkeletonLine className="h-10 w-3/4 rounded-[var(--radius)]" />
      </View>
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
    <View className="gap-3 py-6">
      <View className="gap-1">
        <Text className="text-base font-semibold text-foreground">
          {title}
        </Text>
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
  onPress?: () => void;
}) {
  return (
    <Pressable
      className="rounded-[var(--radius)] px-0 py-3 active:bg-surface-secondary/20"
      onPress={onPress}
    >
      <View className="flex-row items-start justify-between gap-3">
        <View className="min-w-0 flex-1 gap-1">
          <Text className="text-base font-semibold text-foreground">
            {title}
          </Text>
          <Text className="text-sm leading-6 text-muted">{description}</Text>
        </View>

        <View className="max-w-[46%] items-end gap-1 pt-0.5">
          <Text
            numberOfLines={2}
            className="text-sm font-medium text-foreground"
          >
            {value}
          </Text>
          <Text className="text-xs font-medium uppercase tracking-[1px] text-muted">
            Choose
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
        "flex-row items-start gap-3 rounded-[var(--radius)] px-3 py-3",
        selected
          ? "bg-transparent"
          : "bg-transparent active:bg-surface-secondary/18",
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
            <Text className="text-xs font-semibold uppercase tracking-[1px] text-accent/80">
              Selected
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
        "h-10 items-center justify-center rounded-[var(--radius)] border px-4",
        selected
          ? "border-accent/45 bg-surface-secondary/24"
          : "border-border/50 bg-transparent active:bg-surface-secondary/24",
      )}
      onPress={onPress}
    >
      <Text
        className={cn(
          "text-sm font-semibold",
          selected ? "text-foreground" : "text-foreground",
        )}
      >
        {label}
      </Text>
    </Pressable>
  );
}

function ModelPickerSelect({
  models,
  selectedModelId,
  onSelect,
}: {
  models: ModelRecord[];
  selectedModelId?: string;
  onSelect: (modelId: string) => void;
}) {
  const selectedModel =
    models.find((model) => model.id === selectedModelId) ?? null;

  return (
    <Select
      value={
        selectedModel
          ? {
              value: selectedModel.id,
              label: selectedModel.label,
            }
          : undefined
      }
      onValueChange={(option) => {
        if (!option || Array.isArray(option)) {
          return;
        }

        onSelect(option.value);
      }}
      presentation="bottom-sheet"
    >
      <Select.Trigger variant="unstyled" asChild>
        <PickerRow
          title="Selected model"
          description={selectedModel?.remoteId ?? "No model selected yet."}
          value={selectedModel?.label ?? "Choose model"}
        />
      </Select.Trigger>

      <Select.Portal>
        <Select.Overlay className="bg-foreground/20" />
        <Select.Content
          presentation="bottom-sheet"
          snapPoints={["52%"]}
          contentContainerClassName="px-5 pb-safe-offset-6 pt-1"
        >
          <Select.ListLabel className="mb-2 text-xs font-semibold uppercase tracking-[1px] text-muted">
            Choose model
          </Select.ListLabel>
          {models.map((model, index) => (
            <View key={model.id}>
              <Select.Item
                value={model.id}
                label={model.label}
                className="px-0 py-4"
              >
                <View className="flex-1">
                  <Select.ItemLabel className="text-base font-semibold text-foreground" />
                  <Select.ItemDescription className="pt-0.5 text-sm leading-6 text-muted">
                    {model.remoteId}
                  </Select.ItemDescription>
                </View>
                <Select.ItemIndicator className="opacity-80" />
              </Select.Item>
              {index < models.length - 1 ? (
                <Separator className="opacity-20" />
              ) : null}
            </View>
          ))}
        </Select.Content>
      </Select.Portal>
    </Select>
  );
}

function normalizeFocusPrompt(value: string) {
  return value.trim().replace(/\s+/g, " ");
}

function getCadenceDescription(hours: number) {
  if (hours === 24) {
    return "A new challenge arrives daily.";
  }

  if (hours === 12) {
    return "A new challenge arrives every 12 hours.";
  }

  if (hours === 1) {
    return "A new challenge arrives hourly.";
  }

  return `A new challenge arrives every ${hours} hours.`;
}

function CompactCadenceDialog({
  value,
  onValueChange,
}: {
  value: ChallengeCadenceHours;
  onValueChange: (value: ChallengeCadenceHours) => void;
}) {
  const selectedOption =
    CADENCE_OPTIONS.find((option) => option.value === value) ??
    CADENCE_OPTIONS[0];

  return (
    <Select
      value={{
        value: String(selectedOption.value),
        label: selectedOption.label,
      }}
      onValueChange={(option) => {
        if (!option || Array.isArray(option)) {
          return;
        }

        onValueChange(Number(option.value) as ChallengeCadenceHours);
      }}
      presentation="dialog"
    >
      <Select.Trigger variant="unstyled" asChild>
        <Pressable className="px-0 py-3">
          <View className="flex-row items-start justify-between gap-3">
            <Text className="min-w-0 flex-1 text-sm leading-6 text-muted">
              {getCadenceDescription(value)}
            </Text>

            <View className="max-w-[40%] items-end gap-1 pt-0.5">
              <Text
                numberOfLines={1}
                className="text-sm font-medium text-foreground"
              >
                {selectedOption.label}
              </Text>
              <Text className="text-xs font-medium uppercase tracking-[1px] text-muted">
                Change
              </Text>
            </View>
          </View>
        </Pressable>
      </Select.Trigger>

      <Select.Portal>
        <Select.Overlay />
        <Select.Content
          presentation="dialog"
          classNames={{
            wrapper: "px-6",
            content:
              "rounded-[var(--radius)] border border-border/50 bg-background px-4 py-4",
          }}
        >
          <Select.ListLabel>cadence</Select.ListLabel>
          {CADENCE_OPTIONS.map((option, index) => (
            <View key={option.value}>
              <Select.Item value={String(option.value)} label={option.label}>
                <Select.ItemLabel />
                <Select.ItemIndicator />
              </Select.Item>
              {index < CADENCE_OPTIONS.length - 1 ? (
                <Separator className="opacity-25" />
              ) : null}
            </View>
          ))}
        </Select.Content>
      </Select.Portal>
    </Select>
  );
}

export function ParamsScreen() {
  const FOCUS_EDITOR_HEIGHT = 320;
  const initialDraft = useMemo(() => createDefaultSettings(), []);
  const focusPromptPresets = useMemo(() => getFocusPromptPresets(), []);
  const [draft, setDraft] = useState<UserSettingsRecord>(initialDraft);
  const [savedSettings, setSavedSettings] =
    useState<UserSettingsRecord>(initialDraft);
  const [pendingPresetId, setPendingPresetId] = useState<string | null>(null);
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
  const pendingPreset =
    focusPromptPresets.find((preset) => preset.id === pendingPresetId) ?? null;
  const hasCustomFocusPrompt =
    draft.focusPrompt.trim().length > 0 && activeFocusPreset == null;
  const hasUnsavedChanges =
    draft.focusPrompt !== savedSettings.focusPrompt ||
    draft.preferredDifficulty !== savedSettings.preferredDifficulty ||
    draft.preferredMode !== savedSettings.preferredMode ||
    draft.notificationsEnabled !== savedSettings.notificationsEnabled ||
    draft.selectedModelId !== savedSettings.selectedModelId ||
    draft.challengeCadenceHours !== savedSettings.challengeCadenceHours ||
    draft.firstChallengeTimeMinutes !== savedSettings.firstChallengeTimeMinutes;

  const footerStatus = isSaving
    ? "Saving"
    : hasUnsavedChanges
      ? "Unsaved changes"
      : (saveStatus ?? "All changes saved");

  const loadSettings = useCallback(async () => {
    await ensureDefaultModels();
    const [settings, storedModels] = await Promise.all([
      ensureDefaultSettings(),
      listModels({ includeDisabled: true }),
    ]);

    setDraft((current) =>
      isSaving || hasUnsavedChanges ? current : settings,
    );
    setSavedSettings(settings);
    setModels(storedModels);
    setIsLoading(false);
  }, [hasUnsavedChanges, isSaving]);

  useEffect(() => {
    let isMounted = true;

    void (async () => {
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
    })();

    return () => {
      isMounted = false;
    };
  }, []);

  useEffect(() => {
    return subscribeToSettingsRefresh(() => {
      void loadSettings();
    });
  }, [loadSettings]);

  useEffect(() => {
    return subscribeToModelsRefresh(() => {
      void loadSettings();
    });
  }, [loadSettings]);

  function applyFocusPreset(presetPrompt: string) {
    setDraft((current) => ({ ...current, focusPrompt: presetPrompt }));
    setPendingPresetId(null);
  }

  function handleFocusPresetPress(presetId: string, presetPrompt: string) {
    if (activeFocusPreset?.id === presetId) {
      setPendingPresetId(null);
      return;
    }

    if (hasCustomFocusPrompt) {
      setPendingPresetId(presetId);
      return;
    }

    applyFocusPreset(presetPrompt);
  }

  async function handleSaveSettings() {
    setIsSaving(true);
    setSaveStatus(null);

    try {
      const nextSettings: UserSettingsRecord = {
        ...draft,
        challengeCadenceHours: normalizeChallengeCadenceHours(
          draft.challengeCadenceHours ??
            initialDraft.challengeCadenceHours ??
            24,
        ),
        firstChallengeTimeMinutes: normalizeFirstChallengeTimeMinutes(
          draft.firstChallengeTimeMinutes ??
            initialDraft.firstChallengeTimeMinutes ??
            0,
        ),
        updatedAt: new Date().toISOString(),
      };
      const requestedNotifications = nextSettings.notificationsEnabled === true;

      await upsertSettings(nextSettings);
      await refreshReadyChallengeExpirations(nextSettings);
      const notificationResult = await syncChallengeNotifications({
        requestPermissionsIfNeeded: requestedNotifications,
      });
      if (requestedNotifications && !notificationResult.permissionGranted) {
        nextSettings.notificationsEnabled = false;
        await upsertSettings(nextSettings);
      }
      setDraft(nextSettings);
      setSavedSettings(nextSettings);
      setSaveStatus(
        requestedNotifications && !notificationResult.permissionGranted
          ? "Saved, but notifications were not allowed"
          : "Saved locally",
      );
    } catch (error) {
      setSaveStatus(
        error instanceof Error ? error.message : "Failed to save settings",
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
        automaticallyAdjustKeyboardInsets
        keyboardDismissMode="interactive"
        keyboardShouldPersistTaps="handled"
        contentContainerClassName="gap-10 px-5 pb-safe-offset-10 pt-safe-offset-7"
      >
        <PageHeader />

        {isLoading ? <LoadingSettingsSkeleton /> : null}

        {!isLoading ? (
          <View className="gap-10">
            <View className="gap-5 px-1">
              <PanelIntro
                title="Focus prompt"
                description="This prompt steers every fresh challenge. Make it specific enough to feel consistent from session to session."
              />

              <View>
                <ScrollView
                  horizontal
                  showsHorizontalScrollIndicator={false}
                  contentContainerClassName="gap-3 pr-4"
                >
                  {focusPromptPresets.map((preset) => (
                    <FocusPresetChip
                      key={preset.id}
                      label={preset.title}
                      selected={activeFocusPreset?.id === preset.id}
                      onPress={() =>
                        handleFocusPresetPress(preset.id, preset.prompt)
                      }
                    />
                  ))}
                </ScrollView>

              </View>

              <Text className="text-sm leading-6 text-muted">
                {activeFocusPreset?.description ??
                  "Describe the kind of interviews you want to practice and what good challenges should focus on."}
              </Text>

              <View className="border-t border-border/40 pt-4">
                <View className="mb-3 flex-row items-start justify-between gap-3">
                  <View className="min-w-0 flex-1 gap-1">
                    <Text className="text-xs font-semibold uppercase tracking-[1px] text-muted">
                      Focus prompt
                    </Text>
                    <Text className="text-sm font-medium text-foreground">
                      {activeFocusPreset?.title ?? "custom"}
                    </Text>
                  </View>

                  <View className="items-end gap-1">
                    <Text className="text-xs font-medium uppercase tracking-[1px] text-muted">
                      {focusPromptCharacterCount > 0
                        ? `${focusPromptCharacterCount} chars`
                        : "set this before generating"}
                    </Text>
                    {draft.focusPrompt.length > 0 ? (
                      <Pressable
                        onPress={() => {
                          setDraft((current) => ({
                            ...current,
                            focusPrompt: "",
                          }));
                          setPendingPresetId(null);
                        }}
                      >
                        <Text className="text-sm font-medium text-muted">
                          Clear
                        </Text>
                      </Pressable>
                    ) : null}
                  </View>
                </View>

                <TextInput
                  multiline
                  scrollEnabled
                  textAlignVertical="top"
                  placeholder="Example: Senior system design interviews for collaboration and platform products. Push on service boundaries, write amplification, consistency trade-offs, and rollout safety. Avoid toy CRUD prompts and trivia-only questions."
                  value={draft.focusPrompt}
                  onChangeText={(value) => {
                    setDraft((current) => ({
                      ...current,
                      focusPrompt: value,
                    }));
                    setPendingPresetId(null);
                  }}
                  className="rounded-[var(--radius)] border border-border bg-surface px-4 py-3 text-base leading-6 text-foreground"
                  placeholderTextColorClassName="accent-muted"
                  style={{ height: FOCUS_EDITOR_HEIGHT }}
                />
              </View>

              {focusPromptCharacterCount === 0 ? (
                <Text className="text-sm leading-6 text-muted">
                  Do not leave this empty. Start from one of the prompts above
                  or write your own before generating challenges.
                </Text>
              ) : focusPromptCharacterCount < 120 ? (
                <Text className="text-sm leading-6 text-muted">
                  Good start. Add a little more detail about scope, difficulty,
                  or what to avoid so results stay consistent.
                </Text>
              ) : null}
            </View>

            <View className="gap-1 px-1">
              <PanelIntro
                title="Challenge defaults"
                description="Set the default difficulty, help mode, and model for new reps."
              />

              <Row
                title="Difficulty"
                description="Target level for newly generated challenges."
              >
                <View className="flex-row flex-wrap justify-center gap-2 pt-1">
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

              <Separator className="opacity-35" />

              <Row
                title="Mode"
                description="Default help level when you enter a challenge."
              >
                <View className="gap-0 pt-1">
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

              <Separator className="opacity-35" />

              <Row
                title="Model"
                description="Choose the model used across generation and help."
              >
                <ModelPickerSelect
                  models={models}
                  selectedModelId={draft.selectedModelId}
                  onSelect={(modelId: string) => {
                    setDraft((current) => ({
                      ...current,
                      selectedModelId: modelId,
                    }));
                  }}
                />
              </Row>
            </View>

            <View className="gap-1 px-1">
              <PanelIntro
                title="Timing"
                description="Keep scheduling simple: one daily reminder, with challenge cadence handled locally."
              />

              <Row
                title="First of the day"
                description="When the first daily challenge appears."
                value={formatTimeMinutes(firstChallengeTime)}
              >
                {Platform.OS === "web" ? (
                  <Text className="text-sm leading-6 text-muted">
                    Edit this in the native build. Web preview keeps the saved
                    schedule visible without mounting the native time picker.
                  </Text>
                ) : (
                  <View className="items-center overflow-hidden pt-2">
                    <NativeTimePicker
                      value={timeMinutesToDate(firstChallengeTime)}
                      mode="time"
                      display="spinner"
                      minuteInterval={15}
                      onChange={(_, nextValue) => {
                        if (!nextValue) {
                          return;
                        }

                        setDraft((current) => ({
                          ...current,
                          firstChallengeTimeMinutes:
                            dateToTimeMinutes(nextValue),
                        }));
                      }}
                    />
                  </View>
                )}
              </Row>

              <Separator className="opacity-35" />

              <Row
                title="Cadence"
                description="How often a new challenge arrives after that."
              >
                <CompactCadenceDialog
                  value={draft.challengeCadenceHours ?? 24}
                  onValueChange={(value) => {
                    setDraft((current) => ({
                      ...current,
                      challengeCadenceHours: value,
                    }));
                  }}
                />
              </Row>

              <Separator className="opacity-35" />

              <Row
                title="Daily reminder"
                description="One quiet notification at your first challenge time. It does not notify on every cadence slot."
              >
                <View className="gap-0 pt-1">
                  <SelectableRow
                    title="On"
                    description="A single reminder each day at the first challenge time."
                    selected={draft.notificationsEnabled === true}
                    onPress={() =>
                      setDraft((current) => ({
                        ...current,
                        notificationsEnabled: true,
                      }))
                    }
                  />
                  <SelectableRow
                    title="Off"
                    description="No local notifications from drillbit."
                    selected={draft.notificationsEnabled !== true}
                    onPress={() =>
                      setDraft((current) => ({
                        ...current,
                        notificationsEnabled: false,
                      }))
                    }
                  />
                </View>
              </Row>
            </View>

            <View className="gap-3 rounded-[var(--radius)] border border-border/45 bg-surface-secondary/10 px-5 py-5">
              <View className="gap-1">
                <Text className="text-base font-semibold text-foreground">
                  Settings state
                </Text>
                <Text className="text-sm leading-6 text-muted">
                  {footerStatus}
                </Text>
              </View>

              <View className="flex-row gap-3">
                <Button
                  className="flex-1"
                  variant="secondary"
                  onPress={() => {
                    setDraft(savedSettings);
                    setSaveStatus(null);
                  }}
                >
                  <Button.Label>Revert</Button.Label>
                </Button>
                <Button
                  className="flex-1"
                  variant="primary"
                  isDisabled={isSaving || !hasUnsavedChanges}
                  onPress={() => {
                    void handleSaveSettings();
                  }}
                >
                  <Button.Label>{isSaving ? "Saving" : "Save"}</Button.Label>
                </Button>
              </View>
            </View>
          </View>
        ) : null}
      </ScrollView>

      {pendingPreset ? (
        <Dialog
          isOpen
          onOpenChange={(isOpen) => {
            if (!isOpen) {
              setPendingPresetId(null);
            }
          }}
        >
          <Dialog.Portal>
            <Dialog.Overlay />
            <Dialog.Content className="mx-6 rounded-[var(--radius)] border border-border/60 bg-background px-5 py-5">
              <View className="gap-4">
                <View className="gap-1">
                  <Dialog.Title className="text-xl font-semibold text-foreground">
                    Replace custom focus prompt?
                  </Dialog.Title>
                  <Dialog.Description className="text-sm leading-6 text-muted">
                    {`You already have a custom focus prompt. Apply ${pendingPreset.title} to replace it?`}
                  </Dialog.Description>
                </View>

                <View className="flex-row gap-3">
                  <Button
                    className="flex-1"
                    variant="secondary"
                    onPress={() => setPendingPresetId(null)}
                  >
                    <Button.Label>Keep</Button.Label>
                  </Button>
                  <Button
                    className="flex-1"
                    variant="primary"
                    onPress={() => {
                      applyFocusPreset(pendingPreset.prompt);
                    }}
                  >
                    <Button.Label>Replace</Button.Label>
                  </Button>
                </View>
              </View>
            </Dialog.Content>
          </Dialog.Portal>
        </Dialog>
      ) : null}
    </View>
  );
}
