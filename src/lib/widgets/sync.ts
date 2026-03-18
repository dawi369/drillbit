import { debugLog } from "@/lib/debug";
import { buildWidgetViewState } from "@/lib/widgets/state";

let syncPromise: Promise<void> | null = null;

export function syncWidgetState() {
  if (process.env.EXPO_OS !== "ios") {
    return Promise.resolve();
  }

  if (!syncPromise) {
    syncPromise = (async () => {
      try {
        const viewState = await buildWidgetViewState();
        const { default: DrillbitWidget } = await import("@/widgets/drillbit-widget");
        DrillbitWidget.updateSnapshot(viewState);
        DrillbitWidget.reload();
        debugLog("widget", "synced widget snapshot", viewState);
      } catch (error) {
        debugLog("widget", "widget sync failed", error);
      } finally {
        syncPromise = null;
      }
    })();
  }

  return syncPromise;
}
