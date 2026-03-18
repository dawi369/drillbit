import { Asset } from "expo-asset";
import * as FileSystem from "expo-file-system/legacy";

import coachPromptAsset from "@/content/prompts/coach.md";
import defaultFocusPromptAsset from "@/content/prompts/default-focus-prompt.md";
import focusAlgorithmsPromptAsset from "@/content/prompts/focus-algorithms-prompt.md";
import focusBackendPromptAsset from "@/content/prompts/focus-backend-prompt.md";
import focusDebuggingPromptAsset from "@/content/prompts/focus-debugging-prompt.md";
import focusFrontendPromptAsset from "@/content/prompts/focus-frontend-prompt.md";
import generatePromptAsset from "@/content/prompts/generate.md";
import revealPromptAsset from "@/content/prompts/reveal.md";
import summarizePromptAsset from "@/content/prompts/summarize.md";
import type { PromptKind } from "@/lib/storage/types";

export type FocusPromptPreset = {
  id: string;
  title: string;
  description: string;
  prompt: string;
};

type PromptLibrary = {
  focusPromptPresets: FocusPromptPreset[];
  systemPrompts: Record<PromptKind, string>;
};

const promptAssetMap = {
  coach: coachPromptAsset,
  generate: generatePromptAsset,
  reveal: revealPromptAsset,
  summarize: summarizePromptAsset,
} as const;

const defaultFocusPromptPresets: FocusPromptPreset[] = [
  {
    id: "system-design",
    title: "system design",
    description: "Distributed systems, trade-offs, and product-scale architecture.",
    prompt:
      "System design and architecture interview prep focused on multi-step product and infrastructure problems. Emphasize user-facing goals, service boundaries, state and data flow, scaling bottlenecks, consistency trade-offs, rollout strategy, failure modes, and what should be validated next. Prefer rich design prompts over simple CRUD or isolated algorithm-style tasks, and include realistic constraints that force prioritization and discussion.",
  },
  {
    id: "algorithms",
    title: "algorithms",
    description: "Coding reps with decomposition, edge cases, and complexity trade-offs.",
    prompt:
      "Algorithm and coding interview prep focused on medium-to-hard problem solving with clear reasoning, edge cases, and complexity trade-offs. Prefer prompts that reward decomposition, invariants, data structure choice, and communication of approach before code. Avoid obscure puzzle-style tricks unless they illuminate a broader pattern the user should learn.",
  },
  {
    id: "frontend",
    title: "frontend",
    description: "Interactive product work, accessibility, performance, and async UI.",
    prompt:
      "Frontend and product engineering interview prep focused on interactive user-facing systems. Prefer prompts about state management, rendering performance, accessibility, async UI flows, offline behavior, API integration, and trade-offs between polish, complexity, and maintainability. Avoid toy component trivia and instead ask for realistic product constraints that require clear reasoning.",
  },
  {
    id: "backend",
    title: "backend",
    description: "APIs, data flow, reliability, and operational trade-offs.",
    prompt:
      "Backend engineering interview prep focused on APIs, data models, async workflows, reliability, performance, and operational trade-offs. Prefer prompts about service boundaries, storage choices, background jobs, failure handling, caching, throughput, and safe rollout decisions. Avoid shallow CRUD-only questions unless they open into deeper architectural or scaling discussion.",
  },
  {
    id: "debugging",
    title: "debugging",
    description: "Incidents, diagnosis, observability, and rollback judgment.",
    prompt:
      "Backend and debugging interview prep focused on production incidents, ambiguous failures, and diagnosis under pressure. Prefer scenarios that force hypothesis generation, instrumentation choices, log interpretation, rollback judgment, and careful isolation of root cause. Emphasize trade-offs around safety, speed, observability, and communication instead of purely writing fresh feature code.",
  },
];

const defaultPromptLibrary: PromptLibrary = {
  focusPromptPresets: defaultFocusPromptPresets,
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
        const [
          generate,
          coach,
          reveal,
          summarize,
          systemDesignPrompt,
          algorithmsPrompt,
          frontendPrompt,
          backendPrompt,
          debuggingPrompt,
        ] = await Promise.all([
          readMarkdownAsset(promptAssetMap.generate),
          readMarkdownAsset(promptAssetMap.coach),
          readMarkdownAsset(promptAssetMap.reveal),
          readMarkdownAsset(promptAssetMap.summarize),
          readMarkdownAsset(defaultFocusPromptAsset),
          readMarkdownAsset(focusAlgorithmsPromptAsset),
          readMarkdownAsset(focusFrontendPromptAsset),
          readMarkdownAsset(focusBackendPromptAsset),
          readMarkdownAsset(focusDebuggingPromptAsset),
        ]);

        cachedPromptLibrary = {
          focusPromptPresets: [
            {
              id: "system-design",
              title: "system design",
              description:
                "Distributed systems, trade-offs, and product-scale architecture.",
              prompt: systemDesignPrompt.trim(),
            },
            {
              id: "algorithms",
              title: "algorithms",
              description:
                "Coding reps with decomposition, edge cases, and complexity trade-offs.",
              prompt: algorithmsPrompt.trim(),
            },
            {
              id: "frontend",
              title: "frontend",
              description:
                "Interactive product work, accessibility, performance, and async UI.",
              prompt: frontendPrompt.trim(),
            },
            {
              id: "backend",
              title: "backend",
              description:
                "APIs, data flow, reliability, and operational trade-offs.",
              prompt: backendPrompt.trim(),
            },
            {
              id: "debugging",
              title: "debugging",
              description:
                "Incidents, diagnosis, observability, and rollback judgment.",
              prompt: debuggingPrompt.trim(),
            },
          ],
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

export function getFocusPromptPresets() {
  return cachedPromptLibrary?.focusPromptPresets ?? defaultPromptLibrary.focusPromptPresets;
}

export function getDefaultFocusPrompt() {
  return getFocusPromptPresets()[0]?.prompt ?? "";
}
