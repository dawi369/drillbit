import { router } from "expo-router";
import { Button, Menu, Separator, SubMenu } from "heroui-native";
import { Text, View } from "react-native";

import { MODE_OPTIONS } from "@/constants/params";
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
  const selectedModel = availableModels.find((model) => model.id === selectedModelId);
  const selectedModeOption = MODE_OPTIONS.find((option) => option.value === selectedMode);

  return (
    <Menu>
      <Menu.Trigger asChild>
        <Button size="sm" variant="primary">
          <Button.Label>menu</Button.Label>
        </Button>
      </Menu.Trigger>
      <Menu.Portal>
        <Menu.Overlay />
        <Menu.Content presentation="popover" placement="bottom" align="end" width={280}>
          <Menu.Label className="px-1 pb-1">challenge</Menu.Label>
          <View className="flex-row flex-wrap justify-center gap-2 px-2 pb-3 pt-1">
            <MetaPill
              label={isChallengeLoading ? "loading" : (challenge?.topic ?? "no topic")}
            />
            <MetaPill
              label={
                isChallengeLoading ? "loading" : (challenge?.difficulty ?? "no difficulty")
              }
            />
          </View>

          <Separator className="mx-3 my-2 h-px opacity-100" />

          <View>
            <SubMenu>
              <SubMenu.Trigger textValue="mode">
                <View className="flex-1">
                  <Text className="text-sm font-medium text-foreground">mode</Text>
                  <Text className="text-xs text-muted">
                    {selectedModeOption?.label ?? selectedMode}
                  </Text>
                </View>
                <SubMenu.TriggerIndicator />
              </SubMenu.Trigger>
              <SubMenu.Content className="z-20">
                <Menu.Group
                  selectionMode="single"
                  selectedKeys={new Set([selectedMode])}
                  onSelectionChange={(keys) => {
                    const nextMode = Array.from(keys)[0];
                    if (nextMode === "solo" || nextMode === "coach" || nextMode === "reveal") {
                      onSelectMode(nextMode);
                    }
                  }}
                >
                  {MODE_OPTIONS.map((option) => (
                    <Menu.Item key={option.value} id={option.value}>
                      <Menu.ItemIndicator variant="dot" />
                      <View className="flex-1">
                        <Menu.ItemTitle>{option.label}</Menu.ItemTitle>
                        <Menu.ItemDescription>{option.description}</Menu.ItemDescription>
                      </View>
                    </Menu.Item>
                  ))}
                </Menu.Group>
              </SubMenu.Content>
            </SubMenu>
          </View>

          <Separator className="mx-3 my-2 h-px opacity-100" />

          <View>
            <SubMenu>
              <SubMenu.Trigger textValue="models">
                <View className="flex-1">
                  <Text className="text-sm font-medium text-foreground">models</Text>
                  <Text className="text-xs text-muted">
                    {selectedModel?.label ?? "no model selected"}
                  </Text>
                </View>
                <SubMenu.TriggerIndicator />
              </SubMenu.Trigger>
              <SubMenu.Content className="z-20">
                <Menu.Group
                  selectionMode="single"
                  selectedKeys={selectedModelId ? new Set([selectedModelId]) : new Set()}
                  onSelectionChange={(keys) => {
                    const nextModelId = Array.from(keys)[0];
                    const nextModel = availableModels.find((model) => model.id === nextModelId);
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
                        <Menu.ItemDescription>{model.remoteId}</Menu.ItemDescription>
                      </View>
                    </Menu.Item>
                  ))}
                </Menu.Group>
              </SubMenu.Content>
            </SubMenu>
          </View>

          <Separator className="mx-3 my-2 h-px opacity-100" />

          <Menu.Label className="px-1 pb-1 pt-2">actions</Menu.Label>
          <View className="flex-row flex-wrap justify-center gap-2 px-2 pb-2 pt-1">
            <Button size="sm" variant="tertiary" onPress={onSkip} isDisabled={isActionDisabled}>
              <Button.Label>skip</Button.Label>
            </Button>
            <Button size="sm" variant="secondary" onPress={onSave} isDisabled={isActionDisabled}>
              <Button.Label>save</Button.Label>
            </Button>
            <Button size="sm" variant="primary" onPress={onDone} isDisabled={isActionDisabled}>
              <Button.Label>done</Button.Label>
            </Button>
          </View>

          <Separator className="mx-3 my-2 h-px opacity-100" />

          <View className="items-center px-2 pt-1">
            <Button size="sm" variant="tertiary" onPress={() => router.replace("/(tabs)")}>
              <Button.Label>back to params</Button.Label>
            </Button>
          </View>
        </Menu.Content>
      </Menu.Portal>
    </Menu>
  );
}
