import { Alert, Pressable, ScrollView, Text, View } from "react-native";
import { useState } from "react";

import { buildPromptPreviewChain } from "@/lib/prompts/dev-preview";
import { resetDatabase } from "@/lib/storage/database";
import type { PromptKind } from "@/lib/storage/types";

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
        <Text className={`text-sm font-medium ${labelClassName}`}>{actionLabel}</Text>
      </Pressable>
    </View>
  );
}

export default function DevTabScreen() {
  const [activePreviewKind, setActivePreviewKind] = useState<PromptKind | null>(null);
  const [appContextPreview, setAppContextPreview] = useState<string | null>(null);
  const [promptContextPreview, setPromptContextPreview] = useState<string | null>(null);
  const [renderedPromptPreview, setRenderedPromptPreview] = useState<string | null>(null);

  async function handleInspectPromptPipeline(kind: PromptKind) {
    const preview = await buildPromptPreviewChain(kind);

    setActivePreviewKind(kind);
    setAppContextPreview(JSON.stringify(preview.appContext, null, 2));
    setPromptContextPreview(
      preview.promptContext ? JSON.stringify(preview.promptContext, null, 2) : "null",
    );
    setRenderedPromptPreview(preview.renderedPrompt ?? "null");
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
        <Text className="text-3xl font-semibold tracking-tight text-foreground">dev tools</Text>
        <Text className="text-sm leading-6 text-muted">
          Safe local development actions for storage, widget testing, and future challenge tooling.
        </Text>
      </View>

      <DevActionCard
        title="wipe local sqlite"
        description="Delete the local database and recreate empty tables for a clean development state."
        actionLabel="reset database"
        tone="danger"
        onPress={async () => {
          await resetDatabase();
          Alert.alert("database reset", "Local SQLite storage was wiped and recreated.");
        }}
      />

      <DevActionCard
        title="generate challenge"
        description="Create a fresh local challenge from the current params and settings."
        actionLabel="todo: generate challenge"
        todo
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
            <Text className="text-base font-semibold text-foreground">app context preview</Text>
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
            <Text className="text-base font-semibold text-foreground">prompt context preview</Text>
            <Text className="text-sm leading-6 text-muted">
              AI-facing context filtered from the broader app context for `{activePreviewKind}`.
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
            <Text className="text-base font-semibold text-foreground">rendered prompt preview</Text>
            <Text className="text-sm leading-6 text-muted">
              Final english prompt text built from the selected system prompt and prompt context for `{activePreviewKind}`.
            </Text>
          </View>

          <Text selectable className="text-xs leading-5 text-foreground">
            {renderedPromptPreview}
          </Text>
        </View>
      ) : null}
    </ScrollView>
  );
}
