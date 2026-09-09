import type { ModelRecord } from "@/lib/storage/types";

function createSeedModel(remoteId: string, label: string): ModelRecord {
  const now = new Date().toISOString();

  return {
    id: `openrouter:${remoteId}`,
    provider: "openrouter",
    remoteId,
    label,
    isEnabled: true,
    isCustom: false,
    createdAt: now,
    updatedAt: now,
  };
}

export const SEEDED_MODELS: ModelRecord[] = [
  createSeedModel("qwen/qwen3.5-flash-02-23", "qwen 3.5 flash"),
  createSeedModel("deepseek/deepseek-v3.2", "deepseek v3.2"),
  createSeedModel("google/gemini-2.5-flash", "gemini 2.5 flash"),
  createSeedModel("openrouter/hunter-alpha", "hunter alpha"),
];

export function getDefaultSeedModelId() {
  return SEEDED_MODELS[0]?.id;
}

export function createCustomOpenRouterModel(remoteId: string): ModelRecord {
  const trimmedRemoteId = remoteId.trim();
  const now = new Date().toISOString();

  return {
    id: `openrouter:${trimmedRemoteId}`,
    provider: "openrouter",
    remoteId: trimmedRemoteId,
    label: trimmedRemoteId,
    isEnabled: true,
    isCustom: true,
    createdAt: now,
    updatedAt: now,
  };
}
