import { HStack, Spacer, Text, VStack } from "@expo/ui/swift-ui";
import { font, foregroundStyle, padding } from "@expo/ui/swift-ui/modifiers";
import {
  createWidget,
  type WidgetEnvironment,
  type WidgetFamily,
} from "expo-widgets";

import {
  createPlaceholderWidgetState,
  type WidgetViewState,
} from "@/lib/widgets/types";

export const DRILLBIT_WIDGET_NAME = "drillbitWidget";

export type DrillbitWidgetProps = WidgetViewState;

function getWidgetPadding(widgetFamily: WidgetFamily) {
  switch (widgetFamily) {
    case "systemLarge":
      return 18;
    case "systemMedium":
      return 16;
    default:
      return 14;
  }
}

function DrillbitWidgetLayout(
  props: DrillbitWidgetProps,
  environment: WidgetEnvironment,
) {
  "widget";

  const paddingValue = getWidgetPadding(environment.widgetFamily);
  const secondaryColor =
    environment.colorScheme === "dark" ? "#8b98a5" : "#536471";
  const titleColor = environment.colorScheme === "dark" ? "#f5f7fa" : "#0f1419";
  const eyebrow =
    props.status === "in_progress"
      ? "In progress"
      : props.status === "awaiting_next"
        ? "Awaiting next"
        : props.status === "unconfigured"
          ? "Setup"
          : props.status === "error"
            ? "Attention"
            : "Ready";

  return (
    <VStack modifiers={[padding({ all: paddingValue })]}>
      <HStack>
        <Text
          modifiers={[
            font({ size: 12, weight: "semibold" }),
            foregroundStyle("#1d9bf0"),
          ]}
        >
          Drillbit
        </Text>
        <Spacer />
        <Text
          modifiers={[
            font({ size: 12, weight: "medium" }),
            foregroundStyle(secondaryColor),
          ]}
        >
          {eyebrow}
        </Text>
      </HStack>

      <Spacer />

      <VStack>
        <Text
          modifiers={[
            font({ size: 18, weight: "bold" }),
            foregroundStyle(titleColor),
          ]}
        >
          {props.title}
        </Text>
        <Text modifiers={[font({ size: 13 }), foregroundStyle(secondaryColor)]}>
          {props.detail}
        </Text>
      </VStack>

      <Spacer />

      {environment.widgetFamily === "systemMedium" ||
      environment.widgetFamily === "systemLarge" ? (
        <HStack>
          <Text
            modifiers={[
              font({ size: 12, weight: "medium" }),
              foregroundStyle(secondaryColor),
            ]}
          >
            {props.status === "ready" || props.status === "in_progress"
              ? props.challenge.topic
              : "OpenRouter-first"}
          </Text>
          <Spacer />
          <Text
            modifiers={[
              font({ size: 12, weight: "medium" }),
              foregroundStyle("#1d9bf0"),
            ]}
          >
            {props.cta}
          </Text>
        </HStack>
      ) : (
        <Text
          modifiers={[
            font({ size: 12, weight: "medium" }),
            foregroundStyle("#1d9bf0"),
          ]}
        >
          {props.cta}
        </Text>
      )}
    </VStack>
  );
}

const DrillbitWidget = createWidget<DrillbitWidgetProps>(
  DRILLBIT_WIDGET_NAME,
  DrillbitWidgetLayout,
);

export function seedDrillbitWidget() {
  DrillbitWidget.updateSnapshot(createPlaceholderWidgetState());
}

export default DrillbitWidget;
