import DateTimePicker from "@react-native-community/datetimepicker";
import { Link } from "expo-router";
import {
  Button,
  Card,
  Description,
  Input,
  Label,
  TextField,
} from "heroui-native";
import { useEffect, useMemo, useState } from "react";
import { Pressable, ScrollView, Text, View } from "react-native";

import { createCustomOpenRouterModel } from "@/constants/models";
import {
  CADENCE_OPTIONS,
  DIFFICULTY_OPTIONS,
  MODE_OPTIONS,
} from "@/constants/params";
import { cn } from "@/lib/cn";
import {
  createDefaultSettings,
  ensureDefaultModels,
  ensureDefaultSettings,
  listModels,
  normalizeChallengeCadenceHours,
  normalizeFirstChallengeTimeMinutes,
  selectModel,
  setModelEnabled,
  upsertModel,
  upsertSettings,
} from "@/lib/storage/repository";
import type { ModelRecord, UserSettingsRecord } from "@/lib/storage/types";
import {
  dateToTimeMinutes,
  formatTimeMinutes,
  timeMinutesToDate,
} from "@/lib/time";

import { OptionChip } from "./option-chip";

function SummaryPill({ label, value }: { label: string; value: string }) {
  return (
    <View className="rounded-2xl border border-border bg-surface-secondary px-3 py-3">
      <Text className="mb-1 text-[11px] font-medium uppercase tracking-[1.6px] text-muted">
        {label}
      </Text>
      <Text className="text-sm font-medium text-foreground">{value}</Text>
    </View>
  );
}

function ModeCard({
  label,
  description,
  selected,
  onPress,
}: {
  label: string;
  description: string;
  selected: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable
      className={cn(
        "rounded-3xl border px-4 py-4",
        selected
          ? "border-accent bg-accent/10"
          : "border-border bg-surface-secondary",
      )}
      onPress={onPress}
    >
      <Text
        className={cn(
          "mb-1 text-base font-semibold",
          selected ? "text-accent" : "text-foreground",
        )}
      >
        {label}
      </Text>
      <Text className="text-sm leading-6 text-muted">{description}</Text>
    </Pressable>
  );
}

function ModelCard({
  model,
  selected,
  onSelect,
  onDelete,
}: {
  model: ModelRecord;
  selected: boolean;
  onSelect: () => void;
  onDelete: () => void;
}) {
  return (
    <View
      className={cn(
        "gap-3 rounded-3xl border px-4 py-4",
        selected
          ? "border-accent bg-accent/10"
          : "border-border bg-surface-secondary",
      )}
    >
      <View className="gap-1">
        <Text
          className={cn(
            "text-base font-semibold",
            selected ? "text-accent" : "text-foreground",
          )}
        >
          {model.label}
        </Text>
        <Text selectable className="text-sm leading-6 text-muted">
          {model.remoteId}
        </Text>
      </View>

      <View className="flex-row gap-3">
        <Button className="flex-1" variant={selected ? "secondary" : "primary"} onPress={onSelect}>
          <Button.Label>{selected ? "selected" : "select"}</Button.Label>
        </Button>
        <Button className="flex-1" variant="ghost" onPress={onDelete}>
          <Button.Label>delete</Button.Label>
        </Button>
      </View>
    </View>
  );
}

export function ParamsScreen() {
  const initialDraft = useMemo(() => createDefaultSettings(), []);
  const [draft, setDraft] = useState<UserSettingsRecord>(initialDraft);
  const [savedSettings, setSavedSettings] =
    useState<UserSettingsRecord>(initialDraft);
  const [isTimePickerVisible, setTimePickerVisible] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [saveStatus, setSaveStatus] = useState<string | null>(null);
  const [models, setModels] = useState<ModelRecord[]>([]);
  const [customModelInput, setCustomModelInput] = useState("");
  const [modelStatus, setModelStatus] = useState<string | null>(null);

  async function refreshModels() {
    await ensureDefaultModels();
    const storedModels = await listModels({ includeDisabled: true });
    setModels(storedModels);
  }

  const firstChallengeTime =
    draft.firstChallengeTimeMinutes ??
    initialDraft.firstChallengeTimeMinutes ??
    0;
  const cadenceLabel =
    draft.challengeCadenceHours === 24 || draft.challengeCadenceHours == null
      ? "daily"
      : draft.challengeCadenceHours === 1
        ? "every hour"
        : `every ${draft.challengeCadenceHours} hours`;

  const hasUnsavedChanges =
    draft.focusPrompt !== savedSettings.focusPrompt ||
    draft.preferredDifficulty !== savedSettings.preferredDifficulty ||
    draft.preferredMode !== savedSettings.preferredMode ||
    draft.selectedModelId !== savedSettings.selectedModelId ||
    draft.challengeCadenceHours !== savedSettings.challengeCadenceHours ||
    draft.firstChallengeTimeMinutes !== savedSettings.firstChallengeTimeMinutes;

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

      await upsertSettings(nextSettings);
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

  async function handleAddModel() {
    const trimmed = customModelInput.trim();
    if (!trimmed) {
      setModelStatus("paste an openrouter model id first");
      return;
    }

    const model = createCustomOpenRouterModel(trimmed);
    await upsertModel(model);
    await selectModel(model.id);
    setDraft((current) => ({ ...current, selectedModelId: model.id }));
    setCustomModelInput("");
    setModelStatus(`added ${model.remoteId}`);
    await refreshModels();
  }

  async function handleSelectModel(model: ModelRecord) {
    await selectModel(model.id);
    setDraft((current) => ({ ...current, selectedModelId: model.id }));
    setModelStatus(`selected ${model.remoteId}`);
    await refreshModels();
  }

  async function handleDeleteModel(model: ModelRecord) {
    await setModelEnabled(model.id, false);
    const nextSettings = await ensureDefaultSettings();
    setDraft(nextSettings);
    setSavedSettings(nextSettings);
    setModelStatus(`deleted ${model.remoteId}`);
    await refreshModels();
  }

  return (
    <ScrollView
      className="flex-1 bg-background"
      contentInsetAdjustmentBehavior="automatic"
      contentContainerClassName="gap-5 px-5 pb-safe-offset-10 pt-safe-offset-6"
    >
      <View className="gap-2">
        <View className="self-start rounded-full border border-accent/20 bg-accent/10 px-3 py-1.5">
          <Text className="text-[11px] font-medium uppercase tracking-[1.6px] text-accent">
            setup draft
          </Text>
        </View>
        <Text className="text-4xl font-semibold tracking-tight text-foreground">
          params
        </Text>
        <Text className="max-w-2xl text-base leading-7 text-muted">
          Shape the kinds of drills drillbit generates, when they arrive, and
          what help you get to solve them.
        </Text>
      </View>

      <Card className="rounded-[28px] border border-border bg-surface">
        <Card.Body className="gap-4">
          <View className="gap-2">
            <Card.Title className="text-2xl text-foreground">
              current setup
            </Card.Title>
            <Card.Description className="text-sm leading-6 text-muted">
              A quick read of the current draft before we wire persistence and
              challenge generation.
            </Card.Description>
            {isLoading ? (
              <Text className="text-sm text-muted">
                loading saved settings...
              </Text>
            ) : saveStatus ? (
              <Text className="text-sm text-accent">{saveStatus}</Text>
            ) : null}
          </View>

          <View className="gap-3">
            <SummaryPill
              label="Difficulty"
              value={draft.preferredDifficulty ?? "Medium"}
            />
            <SummaryPill
              label="Preferred mode"
              value={draft.preferredMode ?? "AI Coach"}
            />
            <SummaryPill
              label="Schedule"
              value={`${formatTimeMinutes(firstChallengeTime)} · ${cadenceLabel}`}
            />
          </View>
        </Card.Body>
      </Card>

      <Card className="rounded-[28px] border border-border bg-surface">
        <Card.Body className="gap-4">
          <View className="gap-2">
            <Card.Title className="text-xl text-foreground">
              focus prompt
            </Card.Title>
            <Card.Description className="text-sm leading-6 text-muted">
              This is the highest-signal instruction for future generation. Keep
              it specific about topics, depth, and what to avoid.
            </Card.Description>
          </View>

          <TextField>
            <Label>what should drillbit optimize for?</Label>
            <Input
              multiline
              numberOfLines={6}
              placeholder="Example: System design for collaboration tools, queues, data consistency, and trade-off-heavy interviews. Avoid simple CRUD prompts."
              value={draft.focusPrompt}
              onChangeText={(value) =>
                setDraft((current) => ({ ...current, focusPrompt: value }))
              }
              className="min-h-36 items-start py-4"
              textAlignVertical="top"
            />
            <Description>
              Full-screen editor sheet can come next; for now this inline field
              lets us settle the settings shape.
            </Description>
          </TextField>
        </Card.Body>
      </Card>

      <Card className="rounded-[28px] border border-border bg-surface">
        <Card.Body className="gap-4">
          <View className="gap-2">
            <Card.Title className="text-xl text-foreground">
              difficulty
            </Card.Title>
            <Card.Description className="text-sm leading-6 text-muted">
              Keep this separate from the focus prompt so generation can tune
              challenge difficulty without muddying the topic instruction.
            </Card.Description>
          </View>

          <View className="flex-row flex-wrap gap-2">
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
        </Card.Body>
      </Card>

      <Card className="rounded-[28px] border border-border bg-surface">
        <Card.Body className="gap-4">
          <View className="gap-2">
            <Card.Title className="text-xl text-foreground">
              preferred mode
            </Card.Title>
            <Card.Description className="text-sm leading-6 text-muted">
              The widget and modal should both read from one shared default, so
              there is only one mode preference to maintain.
            </Card.Description>
          </View>

          <View className="gap-3">
            {MODE_OPTIONS.map((option) => (
              <ModeCard
                key={option.value}
                label={option.label}
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
        </Card.Body>
      </Card>

      <Card className="rounded-[28px] border border-border bg-surface">
        <Card.Body className="gap-4">
          <View className="gap-2">
            <Card.Title className="text-xl text-foreground">
              schedule
            </Card.Title>
            <Card.Description className="text-sm leading-6 text-muted">
              Pick the first daily drop and then a cadence that divides cleanly
              into 24 hours so refresh windows stay predictable.
            </Card.Description>
          </View>

          <Pressable
            className="rounded-3xl border border-border bg-surface-secondary px-4 py-4"
            onPress={() => setTimePickerVisible((current) => !current)}
          >
            <Text className="mb-1 text-xs font-medium uppercase tracking-[1.6px] text-muted">
              First challenge time
            </Text>
            <Text className="text-base font-semibold text-foreground">
              {formatTimeMinutes(firstChallengeTime)}
            </Text>
          </Pressable>

          {isTimePickerVisible ? (
            <View className="rounded-3xl border border-border bg-surface-secondary px-2 py-2">
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

          <View className="gap-2">
            <Text className="text-xs font-medium uppercase tracking-[1.6px] text-muted">
              Cadence
            </Text>
            <View className="flex-row flex-wrap gap-2">
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
          </View>
        </Card.Body>
      </Card>

      <Card className="rounded-[28px] border border-border bg-surface">
        <Card.Body className="gap-4">
          <View className="gap-2">
            <Card.Title className="text-xl text-foreground">model</Card.Title>
            <Card.Description className="text-sm leading-6 text-muted">
              OpenRouter stays first. The selected model id now lives in local
              settings, backed by a local SQLite model catalog.
            </Card.Description>
          </View>

          <View className="rounded-3xl border border-border bg-surface-secondary px-4 py-4">
            <Text className="mb-1 text-xs font-medium uppercase tracking-[1.6px] text-muted">
              selected model
            </Text>
            <Text
              selectable
              className="text-base font-semibold text-foreground"
            >
              {draft.selectedModelId ?? "not configured"}
            </Text>
          </View>

          <TextField>
            <Label>add openrouter model id</Label>
            <Input
              placeholder="qwen/qwen3.5-flash-02-23"
              value={customModelInput}
              onChangeText={setCustomModelInput}
              autoCapitalize="none"
              autoCorrect={false}
            />
          </TextField>

          <View className="flex-row gap-3">
            <Button className="flex-1" variant="primary" onPress={() => void handleAddModel()}>
              <Button.Label>add model</Button.Label>
            </Button>
            <Button className="flex-1" variant="ghost" onPress={() => void refreshModels()}>
              <Button.Label>refresh models</Button.Label>
            </Button>
          </View>

          {modelStatus ? (
            <Text className="text-sm text-accent">{modelStatus}</Text>
          ) : null}

          <View className="gap-3">
            {models.length === 0 ? (
              <View className="rounded-3xl border border-border bg-surface-secondary px-4 py-4">
                <Text className="text-sm text-muted">no models available</Text>
              </View>
            ) : null}

            {models.map((model) => (
              <ModelCard
                key={model.id}
                model={model}
                selected={draft.selectedModelId === model.id}
                onSelect={() => {
                  void handleSelectModel(model);
                }}
                onDelete={() => {
                  void handleDeleteModel(model);
                }}
              />
            ))}
          </View>
        </Card.Body>
      </Card>

      <Card className="rounded-[28px] border border-accent/20 bg-accent/10">
        <Card.Body className="gap-4">
          <View className="gap-2">
            <Card.Title className="text-lg text-foreground">
              local settings
            </Card.Title>
            <Card.Description className="text-sm leading-6 text-muted">
              This screen saves locally to SQLite. We can keep refining the
              picker flows without changing the underlying settings shape.
            </Card.Description>
          </View>

          <View className="flex-row gap-3">
            <Button
              className="flex-1"
              variant="secondary"
              onPress={() => {
                setDraft(savedSettings);
                setTimePickerVisible(false);
                setSaveStatus(null);
              }}
            >
              <Button.Label>revert draft</Button.Label>
            </Button>
            <Button
              className="flex-1"
              variant="primary"
              isDisabled={isSaving || !hasUnsavedChanges}
              onPress={() => {
                void handleSaveSettings();
              }}
            >
              <Button.Label>
                {isSaving ? "saving..." : "save settings"}
              </Button.Label>
            </Button>
          </View>

          <Link href={{ pathname: "/answer", params: { mode: draft.preferredMode ?? "coach" } }} asChild>
            <Button variant="ghost">
              <Button.Label>open temp answer modal</Button.Label>
            </Button>
          </Link>
        </Card.Body>
      </Card>
    </ScrollView>
  );
}
