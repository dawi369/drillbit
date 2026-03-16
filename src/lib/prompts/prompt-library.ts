import { Asset } from "expo-asset";
import * as FileSystem from "expo-file-system/legacy";

import generatePromptAsset from "@/content/prompts/generate.md";
import coachPromptAsset from "@/content/prompts/coach.md";
import revealPromptAsset from "@/content/prompts/reveal.md";
import summarizePromptAsset from "@/content/prompts/summarize.md";
import defaultFocusPromptAsset from "@/content/prompts/default-focus-prompt.md";
import type { PromptKind } from "@/lib/storage/types";

type PromptLibrary = {
  defaultFocusPrompt: string;
  systemPrompts: Record<PromptKind, string>;
};

const promptAssetMap = {
  generate: generatePromptAsset,
  coach: coachPromptAsset,
  reveal: revealPromptAsset,
  summarize: summarizePromptAsset,
} as const;

const defaultPromptLibrary: PromptLibrary = {
  defaultFocusPrompt:
    "System design and architecture interview prep focused on multi-step product and infrastructure problems. Emphasize user-facing goals, service boundaries, state and data flow, scaling bottlenecks, consistency trade-offs, rollout strategy, failure modes, and what should be validated next. Prefer rich design prompts over simple CRUD or isolated algorithm-style tasks, and include realistic constraints that force prioritization and discussion.",
  systemPrompts: {
    generate:
      "Generate a fresh interview challenge that matches the user's focus, avoids skipped/completed duplicates, and feels concise, high-signal, and discussion-worthy.",
    coach:
      "Coach the user Socratically on the current challenge by probing reasoning, surfacing trade-offs, and withholding full answers unless they explicitly ask.",
    reveal:
      "Reveal a strong structured answer for the current challenge with clear components, trade-offs, pitfalls, and concise justification.",
    summarize:
      "Summarize the user's challenge session into compact reusable memory with clear strengths, weaknesses, and no unnecessary filler.",
  },
};

let cachedPromptLibrary: PromptLibrary | null = null;
let promptLibraryPromise: Promise<PromptLibrary> | null = null;

async function readMarkdownAsset(assetId: number) {
  const asset = Asset.fromModule(assetId);
  await asset.downloadAsync();

  const localUri = asset.localUri ?? asset.uri;
  if (!localUri) {
    throw new Error("Prompt asset URI was unavailable.");
  }

  return FileSystem.readAsStringAsync(localUri);
}

export async function initializePromptLibrary() {
  if (cachedPromptLibrary) {
    return cachedPromptLibrary;
  }

  if (!promptLibraryPromise) {
    promptLibraryPromise = (async () => {
      try {
        const [generate, coach, reveal, summarize, defaultFocusPrompt] =
          await Promise.all([
            readMarkdownAsset(promptAssetMap.generate),
            readMarkdownAsset(promptAssetMap.coach),
            readMarkdownAsset(promptAssetMap.reveal),
            readMarkdownAsset(promptAssetMap.summarize),
            readMarkdownAsset(defaultFocusPromptAsset),
          ]);

        cachedPromptLibrary = {
          defaultFocusPrompt: defaultFocusPrompt.trim(),
          systemPrompts: {
            generate: generate.trim(),
            coach: coach.trim(),
            reveal: reveal.trim(),
            summarize: summarize.trim(),
          },
        };

        return cachedPromptLibrary;
      } catch {
        cachedPromptLibrary = defaultPromptLibrary;
        return cachedPromptLibrary;
      }
    })();
  }

  return promptLibraryPromise;
}

export function getSystemPrompt(kind: PromptKind) {
  return cachedPromptLibrary?.systemPrompts[kind] ?? defaultPromptLibrary.systemPrompts[kind];
}

export function getDefaultFocusPrompt() {
  return cachedPromptLibrary?.defaultFocusPrompt ?? defaultPromptLibrary.defaultFocusPrompt;
}
