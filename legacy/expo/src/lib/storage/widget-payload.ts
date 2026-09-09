import { type WidgetSharedPayload } from "@/lib/storage/types";

const WIDGET_SHARED_PAYLOAD_VERSION = 1;

export function createWidgetSharedPayload(viewState: WidgetSharedPayload["viewState"]): WidgetSharedPayload {
  return {
    version: WIDGET_SHARED_PAYLOAD_VERSION,
    updatedAt: new Date().toISOString(),
    viewState,
  };
}
