import { Button, HStack, Spacer, Text, VStack } from "@expo/ui/swift-ui";
import {
  buttonStyle,
  controlSize,
  font,
  foregroundStyle,
  lineLimit,
  multilineTextAlignment,
  padding,
  tint,
} from "@expo/ui/swift-ui/modifiers";
import {
  createWidget,
  type WidgetEnvironment,
  type WidgetFamily,
} from "expo-widgets";

import {
  createPlaceholderWidgetState,
  type ChallengeMode,
  type WidgetViewState,
} from "@/lib/widgets/types";
import {
  createWidgetAnswerTarget,
  createWidgetTabTarget,
} from "@/lib/widgets/interaction";

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
  const tertiaryColor = environment.colorScheme === "dark" ? "#5f6c77" : "#8899a6";
  const eyebrow =
    props.status === "in_progress"
      ? "in progress"
      : props.status === "awaiting_next"
        ? "awaiting next"
        : props.status === "unconfigured"
          ? "setup"
          : props.status === "error"
            ? "attention"
          : "ready";

  const defaultMode =
    props.status === "ready" || props.status === "in_progress"
      ? (props.preferredMode ?? "solo")
      : "solo";

  const primaryTarget =
    props.status === "ready" || props.status === "in_progress"
      ? createWidgetAnswerTarget(props.challenge.id, defaultMode)
      : props.status === "awaiting_next"
        ? createWidgetTabTarget("memory")
        : createWidgetTabTarget("params");

  function getModeTarget(mode: ChallengeMode) {
    if (props.status !== "ready" && props.status !== "in_progress") {
      return createWidgetTabTarget("params");
    }

    return createWidgetAnswerTarget(props.challenge.id, mode);
  }

  function renderPrimaryButton() {
    return (
      <Button
        label={props.cta}
        target={primaryTarget}
        modifiers={[
          buttonStyle("borderedProminent"),
          controlSize(environment.widgetFamily === "systemSmall" ? "small" : "regular"),
          tint("#1d9bf0"),
        ]}
      />
    );
  }

  function renderModeButtons() {
    if (props.status !== "ready" && props.status !== "in_progress") {
      return null;
    }

    return (
      <HStack>
        <Button
          label="solo"
          target={getModeTarget("solo")}
          modifiers={[buttonStyle("bordered"), controlSize("small"), tint("#1d9bf0")]}
        />
        <Spacer />
        <Button
          label="coach"
          target={getModeTarget("coach")}
          modifiers={[buttonStyle("bordered"), controlSize("small"), tint("#1d9bf0")]}
        />
        <Spacer />
        <Button
          label="reveal"
          target={getModeTarget("reveal")}
          modifiers={[buttonStyle("bordered"), controlSize("small"), tint("#1d9bf0")]}
        />
      </HStack>
    );
  }

  return (
    <VStack modifiers={[padding({ all: paddingValue })]}>
      <HStack>
        <Text
          modifiers={[
            font({ size: 12, weight: "semibold" }),
            foregroundStyle("#1d9bf0"),
          ]}
        >
          drillbit
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
            lineLimit(environment.widgetFamily === "systemSmall" ? 2 : 3),
          ]}
        >
          {props.title}
        </Text>
        <Text
          modifiers={[
            font({ size: 13 }),
            foregroundStyle(secondaryColor),
            lineLimit(environment.widgetFamily === "systemLarge" ? 4 : 3),
            multilineTextAlignment("leading"),
          ]}
        >
          {props.detail}
        </Text>
      </VStack>

      <Spacer />

      {environment.widgetFamily === "systemSmall" ? (
        renderPrimaryButton()
      ) : (
        <VStack>
          <HStack>
            <Text
              modifiers={[
                font({ size: 12, weight: "medium" }),
                foregroundStyle(secondaryColor),
                lineLimit(1),
              ]}
            >
              {props.status === "ready" || props.status === "in_progress"
                ? `${props.challenge.topic}${props.challenge.difficulty ? ` · ${props.challenge.difficulty}` : ""}`
                : props.status === "awaiting_next"
                  ? (props.lastResolvedChallenge?.title ?? "caught up")
                  : "openrouter-first"}
            </Text>
            <Spacer />
            <Text
              modifiers={[
                font({ size: 12, weight: "medium" }),
                foregroundStyle(tertiaryColor),
              ]}
            >
              {props.status === "in_progress" ? "resume" : props.status}
            </Text>
          </HStack>

          <Spacer />

          {renderModeButtons() ?? renderPrimaryButton()}
        </VStack>
      )}

      {environment.widgetFamily === "systemLarge" && props.status === "awaiting_next" ? (
        <Text
          modifiers={[
            font({ size: 12 }),
            foregroundStyle(secondaryColor),
            lineLimit(2),
          ]}
        >
          {props.lastResolvedChallenge
            ? `Last resolved: ${props.lastResolvedChallenge.title}`
            : "Your next challenge will appear automatically."}
        </Text>
      ) : null}
    </VStack>
  );
}

const DrillbitWidget = createWidget<DrillbitWidgetProps>(
  DRILLBIT_WIDGET_NAME,
  DrillbitWidgetLayout,
);

export default DrillbitWidget;

export const DRILLBIT_WIDGET_PLACEHOLDER_STATE = createPlaceholderWidgetState();
