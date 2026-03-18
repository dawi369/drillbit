import { Pressable, Text } from "react-native";

import { cn } from "@/lib/cn";

type OptionChipProps = {
  label: string;
  selected: boolean;
  onPress: () => void;
};

export function OptionChip({ label, selected, onPress }: OptionChipProps) {
  return (
    <Pressable
      className={cn(
        "rounded-full border px-4 py-2.5",
        selected
          ? "border-accent bg-accent/10"
          : "border-border/60 bg-transparent active:bg-surface-secondary/35",
      )}
      onPress={onPress}
    >
      <Text
        className={cn(
          "text-sm font-medium",
          selected ? "text-accent" : "text-foreground",
        )}
      >
        {label}
      </Text>
    </Pressable>
  );
}
