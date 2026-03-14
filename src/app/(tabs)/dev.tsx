import { Alert, Pressable, ScrollView, Text, View } from "react-native";

import { resetDatabase } from "@/lib/storage/database";

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
            Alert.alert("TODO", "This dev action is not wired yet.");
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
        <Text className="text-3xl font-semibold tracking-tight text-foreground">Dev tools</Text>
        <Text className="text-sm leading-6 text-muted">
          Safe local development actions for storage, widget testing, and future challenge tooling.
        </Text>
      </View>

      <DevActionCard
        title="Wipe local SQLite"
        description="Delete the local database and recreate empty tables for a clean development state."
        actionLabel="Reset database"
        tone="danger"
        onPress={async () => {
          await resetDatabase();
          Alert.alert("Database reset", "Local SQLite storage was wiped and recreated.");
        }}
      />

      <DevActionCard
        title="Generate challenge"
        description="Create a fresh local challenge from the current params and settings."
        actionLabel="TODO: Generate challenge"
        todo
      />

      <DevActionCard
        title="Seed widget snapshot"
        description="Push a placeholder or debug widget state into shared payload storage."
        actionLabel="TODO: Seed widget"
        todo
      />

      <DevActionCard
        title="Prune expired challenges"
        description="Delete untouched expired challenges so similar prompts can be generated again."
        actionLabel="TODO: Prune expired"
        todo
      />

      <DevActionCard
        title="Inspect model context"
        description="Build and preview the exact context payload that would be sent to the next model call."
        actionLabel="TODO: Inspect context"
        todo
      />
    </ScrollView>
  );
}
