import { router } from "expo-router";
import { addUserInteractionListener, type UserInteractionEvent } from "expo-widgets";

import { debugLog } from "@/lib/debug";
import { DRILLBIT_WIDGET_NAME } from "@/widgets/drillbit-widget";
import type { ChallengeMode } from "@/lib/widgets/types";

type WidgetTabTarget = "params" | "memory";

export function createWidgetAnswerTarget(challengeId: string, mode: ChallengeMode) {
  return `answer|${challengeId}|${mode}`;
}

export function createWidgetTabTarget(tab: WidgetTabTarget) {
  return `tab|${tab}`;
}

function navigateFromWidgetTarget(target: string) {
  const [kind, first, second] = target.split("|");

  if (kind === "answer" && first && (second === "solo" || second === "coach" || second === "reveal")) {
    router.push({
      pathname: "/answer",
      params: {
        challengeId: first,
        mode: second,
      },
    });
    return;
  }

  if (kind === "tab" && first === "memory") {
    router.replace("/(tabs)/memory");
    return;
  }

  if (kind === "tab" && first === "params") {
    router.replace("/(tabs)");
  }
}

export function handleWidgetInteraction(event: UserInteractionEvent) {
  if (event.source !== DRILLBIT_WIDGET_NAME) {
    return;
  }

  debugLog("widget", "received widget interaction", event);
  navigateFromWidgetTarget(event.target);
}

export function addDrillbitWidgetInteractionListener() {
  if (process.env.EXPO_OS !== "ios") {
    return { remove() {} };
  }

  return addUserInteractionListener(handleWidgetInteraction);
}
