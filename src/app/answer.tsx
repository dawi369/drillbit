import { Stack } from "expo-router";
import { ScrollView, Text, View } from "react-native";

const SESSION_FIELDS = [
  "selectedMode",
  "notesDraft",
  "conversationSummary",
  "updatedAt",
] as const;

export default function AnswerModalScreen() {
  return (
    <>
      <Stack.Screen
        options={{
          title: "answer",
          presentation: "modal",
        }}
      />

      <ScrollView
        className="flex-1 bg-background"
        contentInsetAdjustmentBehavior="automatic"
        contentContainerClassName="gap-5 px-5 pb-safe-offset-10 pt-safe-offset-6"
      >
        <View className="gap-2">
          <Text className="text-3xl font-semibold tracking-tight text-foreground">answer</Text>
          <Text className="text-base leading-7 text-muted">
            Temporary modal scaffold for the interview flow. We will design this carefully once the core session loop is ready.
          </Text>
        </View>

        <View className="rounded-[28px] border border-border bg-surface px-4 py-4">
          <Text className="mb-2 text-lg font-semibold text-foreground">what this modal will hold</Text>
          <Text className="text-sm leading-6 text-muted">
            This will become the primary answering surface for solo, coach, and reveal flows.
          </Text>
        </View>

        <View className="rounded-[28px] border border-accent/20 bg-accent/10 px-4 py-4">
          <Text className="mb-2 text-lg font-semibold text-foreground">todo: wire session state</Text>
          <View className="gap-2">
            {SESSION_FIELDS.map((field) => (
              <Text key={field} className="text-sm leading-6 text-foreground">
                - {field}
              </Text>
            ))}
          </View>
        </View>
      </ScrollView>
    </>
  );
}
