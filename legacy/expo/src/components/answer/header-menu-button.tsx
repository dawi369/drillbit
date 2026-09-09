import { router } from "expo-router";
import { Button, Menu, Separator, SubMenu } from "heroui-native";
import { Pressable, Text, View } from "react-native";

import { MODE_OPTIONS } from "@/constants/params";
import { cn } from "@/lib/cn";
import type { ChallengeRecord, ModelRecord } from "@/lib/storage/types";
import type { ChallengeMode } from "@/lib/widgets/types";

function MetaPill({ label }: { label: string }) {
  return (
    <View className="rounded-[var(--radius)] border border-border bg-surface-secondary px-2 py-1">
      <Text className="text-xs font-medium uppercase tracking-[1px] text-foreground">
        {label}
      </Text>
    </View>
  );
}

function ModeButton({
  label,
  selected,
  disabled,
  onPress,
}: {
  label: string;
  selected: boolean;
  disabled: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable
      className={cn(
        "h-9 flex-1 items-center justify-center rounded-[var(--radius)] border px-3",
        selected
          ? "border-accent/45 bg-surface-secondary/45"
          : "border-border/55 bg-transparent active:bg-surface-secondary/24",
        disabled && "opacity-50",
      )}
      disabled={disabled}
      onPress={onPress}
    >
      <Text
        numberOfLines={1}
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

export function HeaderMenuButton({
  challenge,
  isChallengeLoading,
  selectedMode,
  availableModels,
  selectedModelId,
  onSelectMode,
  onSelectModel,
  onSkip,
  onSave,
  onDone,
  isActionDisabled,
}: {
  challenge: ChallengeRecord | null;
  isChallengeLoading: boolean;
  selectedMode: ChallengeMode;
  availableModels: ModelRecord[];
  selectedModelId?: string;
  onSelectMode: (mode: ChallengeMode) => void;
  onSelectModel: (model: ModelRecord) => void;
  onSkip: () => void;
  onSave: () => void;
  onDone: () => void;
  isActionDisabled: boolean;
}) {
  const selectedModel = availableModels.find(
    (model) => model.id === selectedModelId,
  );
  const selectedModeOption = MODE_OPTIONS.find(
    (option) => option.value === selectedMode,
  );

  return (
    <View className="gap-3">
      <View className="flex-row gap-2">
        {MODE_OPTIONS.map((option) => (
          <ModeButton
            key={option.value}
            label={option.label}
            selected={selectedMode === option.value}
            disabled={isActionDisabled}
            onPress={() => onSelectMode(option.value)}
          />
        ))}
      </View>

      <View className="flex-row items-center justify-between gap-3">
        <View className="min-w-0 flex-1">
          <Text numberOfLines={1} className="text-xs font-medium text-muted">
            {selectedModeOption?.description ??
              "Choose how much help you want for this pass."}
          </Text>
        </View>

        <Menu>
          <Menu.Trigger asChild>
            <Button size="sm" variant="tertiary">
              <Button.Label>Details</Button.Label>
            </Button>
          </Menu.Trigger>
          <Menu.Portal>
            <Menu.Overlay />
            <Menu.Content
              presentation="popover"
              placement="bottom"
              align="end"
              width={280}
            >
              <Menu.Label className="px-1 pb-1">Challenge</Menu.Label>
              <View className="flex-row flex-wrap justify-center gap-2 px-2 pb-3 pt-1">
                <MetaPill
                  label={
                    isChallengeLoading ? "Loading" : (challenge?.topic ?? "No topic")
                  }
                />
                <MetaPill
                  label={
                    isChallengeLoading
                      ? "Loading"
                      : (challenge?.difficulty ?? "No difficulty")
                  }
                />
              </View>

              <Separator className="mx-3 my-2 h-px opacity-100" />

              <View>
                <SubMenu>
                  <SubMenu.Trigger textValue="models">
                    <View className="flex-1">
                      <Text className="text-sm font-medium text-foreground">
                        Model
                      </Text>
                      <Text className="text-xs text-muted">
                        {selectedModel?.label ?? "No model selected"}
                      </Text>
                    </View>
                    <SubMenu.TriggerIndicator />
                  </SubMenu.Trigger>
                  <SubMenu.Content className="z-20">
                    <Menu.Group
                      selectionMode="single"
                      selectedKeys={
                        selectedModelId ? new Set([selectedModelId]) : new Set()
                      }
                      onSelectionChange={(keys) => {
                        const nextModelId = Array.from(keys)[0];
                        const nextModel = availableModels.find(
                          (model) => model.id === nextModelId,
                        );
                        if (nextModel) {
                          onSelectModel(nextModel);
                        }
                      }}
                    >
                      {availableModels.map((model) => (
                        <Menu.Item key={model.id} id={model.id}>
                          <Menu.ItemIndicator variant="dot" />
                          <View className="flex-1">
                            <Menu.ItemTitle>{model.label}</Menu.ItemTitle>
                            <Menu.ItemDescription>
                              {model.remoteId}
                            </Menu.ItemDescription>
                          </View>
                        </Menu.Item>
                      ))}
                    </Menu.Group>
                  </SubMenu.Content>
                </SubMenu>
              </View>

              <Separator className="mx-3 my-2 h-px opacity-100" />

              <View className="items-center px-2 pt-1">
                <Button
                  size="sm"
                  variant="tertiary"
                  onPress={() => router.replace("/(tabs)")}
                >
                  <Button.Label>Back to setup</Button.Label>
                </Button>
              </View>
            </Menu.Content>
          </Menu.Portal>
        </Menu>
      </View>

      <View className="flex-row gap-2">
        <Button
          className="flex-1"
          size="sm"
          variant="tertiary"
          onPress={onSkip}
          isDisabled={isActionDisabled}
        >
          <Button.Label>Skip</Button.Label>
        </Button>
        <Button
          className="flex-1"
          size="sm"
          variant="secondary"
          onPress={onSave}
          isDisabled={isActionDisabled}
        >
          <Button.Label>Save</Button.Label>
        </Button>
        <Button
          className="flex-1"
          size="sm"
          variant="primary"
          onPress={onDone}
          isDisabled={isActionDisabled}
        >
          <Button.Label>Done</Button.Label>
        </Button>
      </View>
    </View>
  );
}
