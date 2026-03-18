import { Tabs } from "heroui-native";

import { cn } from "@/lib/cn";

export function SectionTabLabel({
  label,
  selected,
}: {
  label: string;
  selected: boolean;
}) {
  return (
    <Tabs.Label
      className={cn(
        "text-[15px] font-medium tracking-tight",
        selected ? "text-foreground" : "text-muted",
      )}
    >
      {label}
    </Tabs.Label>
  );
}
