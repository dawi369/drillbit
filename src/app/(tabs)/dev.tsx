import { router } from "expo-router";
import { Button, Input, Label, Separator, Tabs, TextField } from "heroui-native";
import { useCallback, useEffect, useState } from "react";
import { Alert, ScrollView, Text, View } from "react-native";

import { SectionTabLabel } from "@/components/section-tab-label";
import { createCustomOpenRouterModel } from "@/constants/models";
import { subscribeToChallengeRefresh } from "@/lib/challenge-refresh";
import { subscribeToModelsRefresh } from "@/lib/models-refresh";
import { generateChallenge } from "@/lib/challenges/generate";
import { buildPromptPreviewChain } from "@/lib/prompts/dev-preview";
import { subscribeToSettingsRefresh } from "@/lib/settings-refresh";
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

function SectionIntro({
  title,
  description,
}: {
  title: string;
  description: string;
}) {
  return (
    <View className="gap-1 px-1 pb-3">
      <Text className="text-[22px] font-semibold tracking-tight text-foreground">
        {title}
      </Text>
      <Text className="text-sm leading-6 text-muted">{description}</Text>
    </View>
  );
}

function Panel({ children }: { children: React.ReactNode }) {
  return <View className="gap-1 px-1">{children}</View>;
}

function Row({
  title,
  description,
  children,
}: {
  title: string;
  description?: string;
  children: React.ReactNode;
}) {
  return (
    <View className="gap-2.5 py-5">
      <View className="gap-1">
        <Text className="text-[15px] font-semibold text-foreground">{title}</Text>
        {description ? (
          <Text className="text-sm leading-6 text-muted">{description}</Text>
        ) : null}
      </View>
      {children}
    </View>
  );
}

function ActionRow({
  title,
  description,
  actionLabel,
  onPress,
  tone = "default",
  isDisabled = false,
}: {
  title: string;
  description: string;
  actionLabel: string;
  onPress: () => void | Promise<void>;
  tone?: "default" | "danger";
  isDisabled?: boolean;
}) {
  return (
    <View className="gap-2.5 py-5">
      <View className="gap-1">
        <Text className="text-[15px] font-semibold text-foreground">{title}</Text>
        <Text className="text-sm leading-6 text-muted">{description}</Text>
      </View>

      <View className="flex-row">
        <Button
          variant={tone === "danger" ? "danger-soft" : "secondary"}
          isDisabled={isDisabled}
          onPress={() => {
            void onPress();
          }}
        >
          <Button.Label>{actionLabel}</Button.Label>
        </Button>
      </View>
    </View>
  );
}

function ModelListRow({
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
    <View className="gap-2 py-4">
      <View className="flex-row items-start justify-between gap-3">
        <View className="min-w-0 flex-1 gap-1">
          <Text className="text-[15px] font-semibold text-foreground">
            {model.label}
          </Text>
          <Text selectable className="text-sm leading-6 text-muted">
            {model.remoteId}
          </Text>
          <Text className="text-xs leading-5 text-muted">
            {model.isCustom ? "custom" : "seeded"}
          </Text>
        </View>

        <Text className="pt-0.5 text-[11px] font-medium uppercase tracking-[1.4px] text-muted">
          {isSelected ? "selected" : model.provider}
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
  const [activeTab, setActiveTab] = useState("actions");
  const [activePreviewKind, setActivePreviewKind] = useState<PromptKind | null>(null);
  const [appContextPreview, setAppContextPreview] = useState<string | null>(null);
  const [promptContextPreview, setPromptContextPreview] = useState<string | null>(null);
  const [renderedPromptPreview, setRenderedPromptPreview] = useState<string | null>(null);
  const [models, setModels] = useState<ModelRecord[]>([]);
  const [selectedModelId, setSelectedModelId] = useState<string | null>(null);
  const [customModelInput, setCustomModelInput] = useState("");
  const [modelStatus, setModelStatus] = useState<string | null>(null);
  const [generatedChallengePreview, setGeneratedChallengePreview] = useState<string | null>(null);
  const [activeChallengePreview, setActiveChallengePreview] = useState<string | null>(null);
  const [activeChallengeId, setActiveChallengeId] = useState<string | null>(null);

  const refreshModels = useCallback(async () => {
    await ensureDefaultModels();
    const [storedModels, settings] = await Promise.all([
      listModels({ includeDisabled: true }),
      ensureDefaultSettings(),
    ]);

    setModels(storedModels);
    setSelectedModelId(settings.selectedModelId ?? null);
  }, []);

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
    setActiveChallengeId(activeChallenge?.id ?? null);
  }

  useEffect(() => {
    void refreshModels();
    void refreshActiveChallengePreview();
  }, [refreshModels]);

  useEffect(() => {
    return subscribeToModelsRefresh(() => {
      void refreshModels();
    });
  }, [refreshModels]);

  useEffect(() => {
    return subscribeToSettingsRefresh(() => {
      void refreshModels();
    });
  }, [refreshModels]);

  useEffect(() => {
    return subscribeToChallengeRefresh(() => {
      void refreshActiveChallengePreview();
    });
  }, []);

  async function handleInspectPromptPipeline(kind: PromptKind) {
    const preview = await buildPromptPreviewChain(kind);

    setActivePreviewKind(kind);
    setAppContextPreview(JSON.stringify(preview.appContext, null, 2));
    setPromptContextPreview(
      preview.promptContext ? JSON.stringify(preview.promptContext, null, 2) : "null",
    );
    setRenderedPromptPreview(preview.renderedPrompt ?? "null");
    setActiveTab("inspect");
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
      contentContainerClassName="gap-10 px-5 pb-safe-offset-10 pt-safe-offset-7"
    >
      <View className="gap-3">
        <Text className="text-[40px] font-semibold tracking-tight text-foreground">
          lab
        </Text>
        <Text className="max-w-xl text-[15px] leading-6 text-muted">
          Hidden developer tooling for local storage, model catalog work, and prompt inspection.
        </Text>
      </View>

      <Tabs value={activeTab} onValueChange={setActiveTab} variant="secondary" className="gap-5">
        <Tabs.List className="px-1">
          <Tabs.ScrollView scrollAlign="center" contentContainerClassName="min-w-full justify-center gap-2">
            <Tabs.Indicator />
            <Tabs.Trigger value="actions">
              {({ isSelected }) => <SectionTabLabel label="actions" selected={isSelected} />}
            </Tabs.Trigger>
            <Tabs.Trigger value="models">
              {({ isSelected }) => <SectionTabLabel label="models" selected={isSelected} />}
            </Tabs.Trigger>
            <Tabs.Trigger value="inspect">
              {({ isSelected }) => <SectionTabLabel label="inspect" selected={isSelected} />}
            </Tabs.Trigger>
          </Tabs.ScrollView>
        </Tabs.List>

        <Tabs.Content value="actions">
          <Panel>
            <SectionIntro
              title="actions"
              description="Reset local state, generate fresh data, and inspect the active challenge flow."
            />

            <ActionRow
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
                await refreshActiveChallengePreview();
                Alert.alert("database reset", "Local SQLite storage was wiped and recreated.");
              }}
            />

            <Separator className="opacity-35" />

            <ActionRow
              title="generate challenge"
              description="Create a fresh local challenge from the current params and selected model."
              actionLabel="generate challenge"
              onPress={async () => {
                try {
                  const result = await generateChallenge();
                  setGeneratedChallengePreview(JSON.stringify(result.challenge, null, 2));
                  await refreshActiveChallengePreview();
                } catch (error) {
                  Alert.alert(
                    "generation failed",
                    error instanceof Error ? error.message : "Unknown error",
                  );
                }
              }}
            />

            <Separator className="opacity-35" />

            <ActionRow
              title="open answer"
              description="Jump straight into the current active challenge on the answer screen."
              actionLabel="open active challenge"
              isDisabled={!activeChallengeId}
              onPress={async () => {
                if (!activeChallengeId) {
                  return;
                }

                router.push({
                  pathname: "/answer",
                  params: {
                    challengeId: activeChallengeId,
                    mode: "solo",
                  },
                });
              }}
            />

            <Separator className="opacity-35" />

            <ActionRow
              title="inspect active challenge"
              description="Show the single canonical active challenge and the persisted session used by answer."
              actionLabel="refresh active"
              onPress={async () => {
                await refreshActiveChallengePreview();
                setActiveTab("inspect");
              }}
            />

            {generatedChallengePreview ? (
              <>
                <Separator className="opacity-35" />
                <Row
                  title="generated challenge"
                  description="Latest locally saved challenge generated from the current settings."
                >
                  <Text selectable className="text-xs leading-5 text-foreground">
                    {generatedChallengePreview}
                  </Text>
                </Row>
              </>
            ) : null}
          </Panel>
        </Tabs.Content>

        <Tabs.Content value="models">
          <Panel>
            <SectionIntro
              title="models"
              description="Manage the local model catalog used by generation and answer help."
            />

            <Row
              title="add openrouter model"
              description="Paste an OpenRouter model id to add it to the local catalog."
            >
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

              {modelStatus ? <Text className="text-sm text-accent">{modelStatus}</Text> : null}
            </Row>

            <Separator className="opacity-35" />

            <Row
              title="available models"
              description="Select or soft-delete entries from the local catalog."
            >
              <View className="gap-0">
                {models.length === 0 ? (
                  <Text className="text-sm text-muted">no models saved yet</Text>
                ) : null}

                {models.map((model, index) => (
                  <View key={model.id}>
                    <ModelListRow
                      model={model}
                      isSelected={model.id === selectedModelId}
                      onSelect={() => {
                        void handleSelectModel(model);
                      }}
                      onDelete={() => {
                        void handleDeleteModel(model);
                      }}
                    />
                    {index < models.length - 1 ? <Separator className="opacity-25" /> : null}
                  </View>
                ))}
              </View>
            </Row>
          </Panel>
        </Tabs.Content>

        <Tabs.Content value="inspect">
          <Panel>
            <SectionIntro
              title="inspect"
              description="Preview prompt pipelines and inspect active challenge state."
            />

            <Row
              title="prompt pipelines"
              description="Build app context, prompt context, and rendered prompt for any supported prompt kind."
            >
              <View className="flex-row flex-wrap gap-3">
                <Button variant="secondary" onPress={() => void handleInspectPromptPipeline("generate")}>
                  <Button.Label>generate</Button.Label>
                </Button>
                <Button variant="secondary" onPress={() => void handleInspectPromptPipeline("coach")}>
                  <Button.Label>coach</Button.Label>
                </Button>
                <Button variant="secondary" onPress={() => void handleInspectPromptPipeline("reveal")}>
                  <Button.Label>reveal</Button.Label>
                </Button>
                <Button variant="secondary" onPress={() => void handleInspectPromptPipeline("summarize")}>
                  <Button.Label>summarize</Button.Label>
                </Button>
              </View>
            </Row>

            {activeChallengePreview ? (
              <>
                <Separator className="opacity-35" />
                <Row
                  title="active challenge"
                  description="Canonical current challenge plus persisted session state."
                >
                  <Text selectable className="text-xs leading-5 text-foreground">
                    {activeChallengePreview}
                  </Text>
                </Row>
              </>
            ) : null}

            {appContextPreview ? (
              <>
                <Separator className="opacity-35" />
                <Row
                  title="app context preview"
                  description={`Structured app-side context for ${activePreviewKind}.`}
                >
                  <Text selectable className="text-xs leading-5 text-foreground">
                    {appContextPreview}
                  </Text>
                </Row>
              </>
            ) : null}

            {promptContextPreview ? (
              <>
                <Separator className="opacity-35" />
                <Row
                  title="prompt context preview"
                  description={`AI-facing context filtered for ${activePreviewKind}.`}
                >
                  <Text selectable className="text-xs leading-5 text-foreground">
                    {promptContextPreview}
                  </Text>
                </Row>
              </>
            ) : null}

            {renderedPromptPreview ? (
              <>
                <Separator className="opacity-35" />
                <Row
                  title="rendered prompt preview"
                  description={`Final prompt text built for ${activePreviewKind}.`}
                >
                  <Text selectable className="text-xs leading-5 text-foreground">
                    {renderedPromptPreview}
                  </Text>
                </Row>
              </>
            ) : null}
          </Panel>
        </Tabs.Content>
      </Tabs>
    </ScrollView>
  );
}
