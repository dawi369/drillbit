import DateTimePicker from "@react-native-community/datetimepicker";
import { Button, Card, Description, Input, Label, TextField } from "heroui-native";
import { useMemo, useState } from "react";
import { Pressable, ScrollView, Text, View } from "react-native";

import { CADENCE_OPTIONS, DIFFICULTY_OPTIONS, MODE_OPTIONS } from "@/constants/params";
import { cn } from "@/lib/cn";
import { createDefaultSettings } from "@/lib/storage/repository";
import type { UserSettingsRecord } from "@/lib/storage/types";
import { dateToTimeMinutes, formatTimeMinutes, timeMinutesToDate } from "@/lib/time";

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
        selected ? "border-accent bg-accent/10" : "border-border bg-surface-secondary",
      )}
      onPress={onPress}
    >
      <Text className={cn("mb-1 text-base font-semibold", selected ? "text-accent" : "text-foreground")}>
        {label}
      </Text>
      <Text className="text-sm leading-6 text-muted">{description}</Text>
    </Pressable>
  );
}

export function ParamsScreen() {
  const initialDraft = useMemo(() => createDefaultSettings(), []);
  const [draft, setDraft] = useState<UserSettingsRecord>(initialDraft);
  const [isTimePickerVisible, setTimePickerVisible] = useState(false);

  const firstChallengeTime = draft.firstChallengeTimeMinutes ?? initialDraft.firstChallengeTimeMinutes ?? 0;
  const cadenceLabel =
    draft.challengeCadenceHours === 24 || draft.challengeCadenceHours == null
      ? "Daily"
      : `Every ${draft.challengeCadenceHours} hours`;

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
        <Text className="text-4xl font-semibold tracking-tight text-foreground">Params</Text>
        <Text className="max-w-2xl text-base leading-7 text-muted">
          Shape the kinds of drills drillbit generates, when they arrive, and how the widget opens the modal by default.
        </Text>
      </View>

      <Card className="rounded-[28px] border border-border bg-surface">
        <Card.Body className="gap-4">
          <View className="gap-2">
            <Card.Title className="text-2xl text-foreground">Current setup</Card.Title>
            <Card.Description className="text-sm leading-6 text-muted">
              A quick read of the current draft before we wire persistence and challenge generation.
            </Card.Description>
          </View>

          <View className="gap-3">
            <SummaryPill label="Difficulty" value={draft.preferredDifficulty ?? "Medium"} />
            <SummaryPill label="Preferred mode" value={draft.preferredMode ?? "AI Coach"} />
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
            <Card.Title className="text-xl text-foreground">Focus prompt</Card.Title>
            <Card.Description className="text-sm leading-6 text-muted">
              This is the highest-signal instruction for future generation. Keep it specific about topics, depth, and what to avoid.
            </Card.Description>
          </View>

          <TextField>
            <Label>What should drillbit optimize for?</Label>
            <Input
              multiline
              numberOfLines={6}
              placeholder="Example: System design for collaboration tools, queues, data consistency, and trade-off-heavy interviews. Avoid simple CRUD prompts."
              value={draft.focusPrompt}
              onChangeText={(value) => setDraft((current) => ({ ...current, focusPrompt: value }))}
              className="min-h-36 items-start py-4"
              textAlignVertical="top"
            />
            <Description>
              Full-screen editor sheet can come next; for now this inline field lets us settle the settings shape.
            </Description>
          </TextField>
        </Card.Body>
      </Card>

      <Card className="rounded-[28px] border border-border bg-surface">
        <Card.Body className="gap-4">
          <View className="gap-2">
            <Card.Title className="text-xl text-foreground">Difficulty</Card.Title>
            <Card.Description className="text-sm leading-6 text-muted">
              Keep this separate from the focus prompt so generation can tune challenge difficulty without muddying the topic instruction.
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
            <Card.Title className="text-xl text-foreground">Preferred mode</Card.Title>
            <Card.Description className="text-sm leading-6 text-muted">
              The widget and modal should both read from one shared default, so there is only one mode preference to maintain.
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
            <Card.Title className="text-xl text-foreground">Schedule</Card.Title>
            <Card.Description className="text-sm leading-6 text-muted">
              Pick the first daily drop and then a cadence that divides cleanly into 24 hours so refresh windows stay predictable.
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
            <Card.Title className="text-xl text-foreground">Model</Card.Title>
            <Card.Description className="text-sm leading-6 text-muted">
              OpenRouter stays first. We can add the real picker and BYOK controls once the storage flow is wired.
            </Card.Description>
          </View>

          <View className="rounded-3xl border border-border bg-surface-secondary px-4 py-4">
            <Text className="mb-1 text-xs font-medium uppercase tracking-[1.6px] text-muted">
              Default model
            </Text>
            <Text selectable className="text-base font-semibold text-foreground">
              {draft.defaultModel ?? "Not configured"}
            </Text>
          </View>

          <Button variant="ghost" onPress={() => {}}>
            <Button.Label>TODO: open model picker</Button.Label>
          </Button>
        </Card.Body>
      </Card>

      <Card className="rounded-[28px] border border-accent/20 bg-accent/10">
        <Card.Body className="gap-4">
          <View className="gap-2">
            <Card.Title className="text-lg text-foreground">Draft-only for now</Card.Title>
            <Card.Description className="text-sm leading-6 text-muted">
              This screen is interactive and reflects the settings model, but it is not persisted yet. We can wire save/load next after the UI feels right.
            </Card.Description>
          </View>

          <View className="flex-row gap-3">
            <Button
              className="flex-1"
              variant="secondary"
              onPress={() => {
                setDraft(createDefaultSettings());
                setTimePickerVisible(false);
              }}
            >
              <Button.Label>Reset draft</Button.Label>
            </Button>
            <Button className="flex-1" variant="ghost" onPress={() => {}}>
              <Button.Label>TODO: save locally</Button.Label>
            </Button>
          </View>
        </Card.Body>
      </Card>
    </ScrollView>
  );
}
