import { Button, Input, Label, TextField } from "heroui-native";
import { useEffect, useState } from "react";
import { Alert, Pressable, ScrollView, Text, View } from "react-native";

import { createCustomOpenRouterModel } from "@/constants/models";
import { generateChallenge } from "@/lib/challenges/generate";
import { buildPromptPreviewChain } from "@/lib/prompts/dev-preview";
import { resetDatabase } from "@/lib/storage/database";
import {
  ensureDefaultModels,
  ensureDefaultSettings,
  getChallengeSession,
  getCurrentActiveChallenge,
  getSelectedModel,
  listModels,
  selectModel,
  setModelEnabled,
  upsertModel,
} from "@/lib/storage/repository";
import type { ModelRecord, PromptKind } from "@/lib/storage/types";

type DevActionCardProps = {
  title: string;
  description: string;
  actionLabel: string;
  onPress?: () => void | Promise<void>;
  todo?: boolean;
  tone?: "default" | "danger";
};

function DevActionCard({
  title,
  description,
  actionLabel,
  onPress,
  todo = false,
  tone = "default",
}: DevActionCardProps) {
  const buttonClassName =
    tone === "danger"
      ? "border-danger/20 bg-danger/10"
      : "border-accent/20 bg-accent/10";

  const labelClassName = tone === "danger" ? "text-danger" : "text-accent";

  return (
    <View className="gap-3 rounded-3xl border border-border bg-surface px-4 py-4">
      <View className="gap-1">
        <Text className="text-base font-semibold text-foreground">{title}</Text>
        <Text className="text-sm leading-6 text-muted">{description}</Text>
      </View>

      <Pressable
        className={`rounded-2xl border px-3 py-3 ${buttonClassName}`}
        disabled={!onPress || todo}
        onPress={() => {
          if (todo) {
            Alert.alert("todo", "This dev action is not wired yet.");
            return;
          }

          void onPress?.();
        }}
      >
        <Text className={`text-sm font-medium ${labelClassName}`}>
          {actionLabel}
        </Text>
      </Pressable>
    </View>
  );
}

function ModelRow({
  model,
  isSelected,
  onSelect,
  onDelete,
}: {
  model: ModelRecord;
  isSelected: boolean;
  onSelect: () => void;
  onDelete: () => void;
}) {
  return (
    <View
      className={`gap-3 rounded-3xl border px-4 py-4 ${
        isSelected
          ? "border-accent bg-accent/10"
          : "border-border bg-surface-secondary"
      }`}
    >
      <View className="gap-1">
        <View className="flex-row items-center justify-between gap-3">
          <Text className="text-base font-semibold text-foreground">
            {model.label}
          </Text>
          <View
            className={`rounded-full px-2 py-1 ${
              isSelected ? "bg-accent/20" : "bg-background"
            }`}
          >
            <Text className="text-[10px] font-medium uppercase tracking-[1.2px] text-muted">
              {isSelected ? "selected" : model.provider}
            </Text>
          </View>
        </View>

        <Text selectable className="text-sm leading-6 text-muted">
          {model.remoteId}
        </Text>

        <Text className="text-xs leading-5 text-muted">
          {model.isCustom ? "custom" : "seeded"}
        </Text>
      </View>

      <View className="flex-row gap-3">
        <Button className="flex-1" variant={isSelected ? "secondary" : "primary"} onPress={onSelect}>
          <Button.Label>{isSelected ? "selected" : "select"}</Button.Label>
        </Button>
        <Button className="flex-1" variant="ghost" onPress={onDelete}>
          <Button.Label>delete</Button.Label>
        </Button>
      </View>
    </View>
  );
}

export default function DevTabScreen() {
  const [activePreviewKind, setActivePreviewKind] = useState<PromptKind | null>(
    null,
  );
  const [appContextPreview, setAppContextPreview] = useState<string | null>(
    null,
  );
  const [promptContextPreview, setPromptContextPreview] = useState<
    string | null
  >(null);
  const [renderedPromptPreview, setRenderedPromptPreview] = useState<
    string | null
  >(null);
  const [models, setModels] = useState<ModelRecord[]>([]);
  const [selectedModelId, setSelectedModelId] = useState<string | null>(null);
  const [customModelInput, setCustomModelInput] = useState("");
  const [modelStatus, setModelStatus] = useState<string | null>(null);
  const [generatedChallengePreview, setGeneratedChallengePreview] = useState<
    string | null
  >(null);
  const [activeChallengePreview, setActiveChallengePreview] = useState<string | null>(
    null,
  );

  async function refreshModels() {
    await ensureDefaultModels();
    const [storedModels, settings] = await Promise.all([
      listModels({ includeDisabled: true }),
      ensureDefaultSettings(),
    ]);

    setModels(storedModels);
    setSelectedModelId(settings.selectedModelId ?? null);
  }

  async function refreshActiveChallengePreview() {
    const activeChallenge = await getCurrentActiveChallenge();
    const activeSession = activeChallenge
      ? await getChallengeSession(activeChallenge.id)
      : null;

    setActiveChallengePreview(
      JSON.stringify(
        {
          activeChallenge,
          activeSession,
        },
        null,
        2,
      ),
    );
  }

  useEffect(() => {
    void refreshModels();
    void refreshActiveChallengePreview();
  }, []);

  async function handleInspectPromptPipeline(kind: PromptKind) {
    const preview = await buildPromptPreviewChain(kind);

    setActivePreviewKind(kind);
    setAppContextPreview(JSON.stringify(preview.appContext, null, 2));
    setPromptContextPreview(
      preview.promptContext
        ? JSON.stringify(preview.promptContext, null, 2)
        : "null",
    );
    setRenderedPromptPreview(preview.renderedPrompt ?? "null");
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
    setCustomModelInput("");
    setModelStatus(`added ${model.remoteId}`);
    await refreshModels();
  }

  async function handleDeleteModel(model: ModelRecord) {
    await setModelEnabled(model.id, false);
    setModelStatus(`deleted ${model.remoteId}`);
    await refreshModels();
  }

  async function handleSelectModel(model: ModelRecord) {
    await selectModel(model.id);
    const selectedModel = await getSelectedModel();
    setSelectedModelId(selectedModel?.id ?? null);
    setModelStatus(`selected ${model.remoteId}`);
    await refreshModels();
  }

  if (!__DEV__) {
    return null;
  }

  return (
    <ScrollView
      className="flex-1 bg-background"
      contentInsetAdjustmentBehavior="automatic"
      contentContainerClassName="gap-4 px-5 pb-10 pt-6"
    >
      <View className="gap-1">
        <Text className="text-3xl font-semibold tracking-tight text-foreground">
          dev tools
        </Text>
        <Text className="text-sm leading-6 text-muted">
          Local development actions for storage, model management, widget
          testing, and future challenge tooling.
        </Text>
      </View>

      <DevActionCard
        title="wipe local sqlite"
        description="Delete the local database and recreate empty tables for a clean development state."
        actionLabel="reset database"
        tone="danger"
        onPress={async () => {
          await resetDatabase();
          setAppContextPreview(null);
          setPromptContextPreview(null);
          setRenderedPromptPreview(null);
          setCustomModelInput("");
          setModelStatus(null);
          await refreshModels();
          setGeneratedChallengePreview(null);
          setActiveChallengePreview(null);
          Alert.alert(
            "database reset",
            "Local SQLite storage was wiped and recreated.",
          );
        }}
      />

      <View className="gap-4 rounded-3xl border border-border bg-surface px-4 py-4">
        <View className="gap-1">
          <Text className="text-base font-semibold text-foreground">
            manage models
          </Text>
          <Text className="text-sm leading-6 text-muted">
            Paste an OpenRouter model id, add it to the available models, then
            select or delete entries from the local catalog.
          </Text>
        </View>

        <TextField>
          <Label>openrouter model id</Label>
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
            <Button.Label>refresh</Button.Label>
          </Button>
        </View>

        {modelStatus ? (
          <Text className="text-sm text-accent">{modelStatus}</Text>
        ) : null}

        <View className="gap-3">
          {models.length === 0 ? (
            <View className="rounded-3xl border border-border bg-surface-secondary px-4 py-4">
              <Text className="text-sm text-muted">no models saved yet</Text>
            </View>
          ) : null}

          {models.map((model) => (
            <ModelRow
              key={model.id}
              model={model}
              isSelected={model.id === selectedModelId}
              onSelect={() => {
                void handleSelectModel(model);
              }}
              onDelete={() => {
                void handleDeleteModel(model);
              }}
            />
          ))}
        </View>
      </View>

      <DevActionCard
        title="generate challenge"
        description="Create a fresh local challenge from the current params and selected model."
        actionLabel="generate challenge"
        onPress={async () => {
          try {
            const result = await generateChallenge();
            setGeneratedChallengePreview(JSON.stringify(result.challenge, null, 2));
            await refreshActiveChallengePreview();
            Alert.alert("challenge generated", result.challenge.title);
          } catch (error) {
            Alert.alert(
              "generation failed",
              error instanceof Error ? error.message : "Unknown error",
            );
          }
        }}
      />

      <DevActionCard
        title="inspect active challenge"
        description="Show the single canonical active challenge and its session state as the app currently resolves it."
        actionLabel="inspect active"
        onPress={async () => {
          await refreshActiveChallengePreview();
        }}
      />

      <DevActionCard
        title="seed widget snapshot"
        description="Push a placeholder or debug widget state into shared payload storage."
        actionLabel="todo: seed widget"
        todo
      />

      <DevActionCard
        title="prune expired challenges"
        description="Delete untouched expired challenges so similar prompts can be generated again."
        actionLabel="todo: prune expired"
        todo
      />

      <DevActionCard
        title="inspect generate pipeline"
        description="Build the app context, prompt context, and final rendered prompt for a generate call."
        actionLabel="inspect generate"
        onPress={async () => {
          await handleInspectPromptPipeline("generate");
        }}
      />

      <DevActionCard
        title="inspect coach pipeline"
        description="Preview the full context chain for an in-progress coach call using seeded dev challenge data."
        actionLabel="inspect coach"
        onPress={async () => {
          await handleInspectPromptPipeline("coach");
        }}
      />

      <DevActionCard
        title="inspect reveal pipeline"
        description="Preview the full context chain for a reveal call using seeded dev challenge data."
        actionLabel="inspect reveal"
        onPress={async () => {
          await handleInspectPromptPipeline("reveal");
        }}
      />

      <DevActionCard
        title="inspect summarize pipeline"
        description="Preview the full context chain for post-session summarization using seeded dev challenge data."
        actionLabel="inspect summarize"
        onPress={async () => {
          await handleInspectPromptPipeline("summarize");
        }}
      />

      {appContextPreview ? (
        <View className="gap-3 rounded-3xl border border-border bg-surface px-4 py-4">
          <View className="gap-1">
            <Text className="text-base font-semibold text-foreground">
              app context preview
            </Text>
            <Text className="text-sm leading-6 text-muted">
              Structured app-side context assembled for `{activePreviewKind}`.
            </Text>
          </View>

          <Text selectable className="text-xs leading-5 text-foreground">
            {appContextPreview}
          </Text>
        </View>
      ) : null}

      {promptContextPreview ? (
        <View className="gap-3 rounded-3xl border border-border bg-surface px-4 py-4">
          <View className="gap-1">
            <Text className="text-base font-semibold text-foreground">
              prompt context preview
            </Text>
            <Text className="text-sm leading-6 text-muted">
              AI-facing context filtered from the broader app context for `
              {activePreviewKind}`.
            </Text>
          </View>

          <Text selectable className="text-xs leading-5 text-foreground">
            {promptContextPreview}
          </Text>
        </View>
      ) : null}

      {renderedPromptPreview ? (
        <View className="gap-3 rounded-3xl border border-border bg-surface px-4 py-4">
          <View className="gap-1">
            <Text className="text-base font-semibold text-foreground">
              rendered prompt preview
            </Text>
            <Text className="text-sm leading-6 text-muted">
              Final english prompt text built from the selected system prompt
              and prompt context for `{activePreviewKind}`.
            </Text>
          </View>

          <Text selectable className="text-xs leading-5 text-foreground">
            {renderedPromptPreview}
          </Text>
        </View>
      ) : null}

      {generatedChallengePreview ? (
        <View className="gap-3 rounded-3xl border border-border bg-surface px-4 py-4">
          <View className="gap-1">
            <Text className="text-base font-semibold text-foreground">
              generated challenge
            </Text>
            <Text className="text-sm leading-6 text-muted">
              Latest locally saved challenge generated with the selected model.
            </Text>
          </View>

          <Text selectable className="text-xs leading-5 text-foreground">
            {generatedChallengePreview}
          </Text>
        </View>
      ) : null}

      {activeChallengePreview ? (
        <View className="gap-3 rounded-3xl border border-border bg-surface px-4 py-4">
          <View className="gap-1">
            <Text className="text-base font-semibold text-foreground">
              active challenge
            </Text>
            <Text className="text-sm leading-6 text-muted">
              Canonical current challenge plus the persisted session used by the
              answer screen.
            </Text>
          </View>

          <Text selectable className="text-xs leading-5 text-foreground">
            {activeChallengePreview}
          </Text>
        </View>
      ) : null}
    </ScrollView>
  );
}
