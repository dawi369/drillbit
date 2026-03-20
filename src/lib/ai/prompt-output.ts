import type { ChallengeSummaryRecord } from "@/lib/storage/types";

export type GeneratedChallengeDraft = {
  title: string;
  teaser: string;
  topic: string;
};

export type CoachAssistantOutput = {
  guidance: string;
};

export type RevealAssistantOutput = {
  guidance: string;
  answer: string;
};

export type GeneratedChallengeSummary = Pick<
  ChallengeSummaryRecord,
  "shortSummary" | "shortFeedback" | "strengths" | "weaknesses" | "tags" | "completionScore"
>;

function extractJsonText(rawText: string) {
  const trimmed = rawText.trim();
  const fencedMatch = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/i);

  if (fencedMatch?.[1]) {
    return fencedMatch[1].trim();
  }

  const firstBraceIndex = trimmed.indexOf("{");
  const lastBraceIndex = trimmed.lastIndexOf("}");

  if (firstBraceIndex >= 0 && lastBraceIndex > firstBraceIndex) {
    return trimmed.slice(firstBraceIndex, lastBraceIndex + 1);
  }

  return trimmed;
}

function parseJsonRecord(rawText: string) {
  const jsonText = extractJsonText(rawText);
  const parsed = JSON.parse(jsonText) as unknown;

  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("Model output was not a JSON object.");
  }

  return parsed as Record<string, unknown>;
}

function readRequiredString(record: Record<string, unknown>, key: string) {
  const value = record[key];

  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`Model output field '${key}' must be a non-empty string.`);
  }

  return value.trim();
}

function readStringArray(record: Record<string, unknown>, key: string) {
  const value = record[key];

  if (!Array.isArray(value)) {
    throw new Error(`Model output field '${key}' must be an array of strings.`);
  }

  const normalized = value
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim())
    .filter(Boolean);

  if (normalized.length !== value.length) {
    throw new Error(`Model output field '${key}' must contain only non-empty strings.`);
  }

  return normalized;
}

function readCompletionScore(record: Record<string, unknown>) {
  const value = record.completionScore;

  if (typeof value !== "number" || Number.isNaN(value)) {
    throw new Error("Model output field 'completionScore' must be a number.");
  }

  if (value < 0 || value > 1) {
    throw new Error("Model output field 'completionScore' must be between 0 and 1.");
  }

  return value;
}

export function parseGenerateChallengeOutput(rawText: string): GeneratedChallengeDraft {
  const record = parseJsonRecord(rawText);

  return {
    title: readRequiredString(record, "title"),
    teaser: readRequiredString(record, "teaser"),
    topic: readRequiredString(record, "topic"),
  };
}

export function parseCoachOutput(rawText: string): CoachAssistantOutput {
  try {
    const record = parseJsonRecord(rawText);

    return {
      guidance: readRequiredString(record, "guidance"),
    };
  } catch {
    const fallback = extractJsonText(rawText).trim();

    if (!fallback) {
      throw new Error("Model output field 'guidance' must be a non-empty string.");
    }

    return {
      guidance: fallback,
    };
  }
}

export function parseRevealOutput(rawText: string): RevealAssistantOutput {
  try {
    const record = parseJsonRecord(rawText);

    return {
      guidance: readRequiredString(record, "guidance"),
      answer: readRequiredString(record, "answer"),
    };
  } catch {
    const jsonText = extractJsonText(rawText).trim();
    const firstParagraphBreak = jsonText.indexOf("\n\n");
    const firstLineBreak = jsonText.indexOf("\n");
    const splitIndex =
      firstParagraphBreak >= 0
        ? firstParagraphBreak
        : firstLineBreak >= 0
          ? firstLineBreak
          : -1;

    const guidance =
      splitIndex >= 0 ? jsonText.slice(0, splitIndex).trim() : jsonText.trim();
    const answer = splitIndex >= 0 ? jsonText.slice(splitIndex).trim() : jsonText.trim();

    if (!guidance || !answer) {
      throw new Error("Model output field 'guidance' must be a non-empty string.");
    }

    return {
      guidance,
      answer,
    };
  }
}

export function parseSummarizeOutput(rawText: string): GeneratedChallengeSummary {
  const record = parseJsonRecord(rawText);

  return {
    shortSummary: readRequiredString(record, "shortSummary"),
    shortFeedback: readRequiredString(record, "shortFeedback"),
    strengths: readStringArray(record, "strengths"),
    weaknesses: readStringArray(record, "weaknesses"),
    tags: readStringArray(record, "tags"),
    completionScore: readCompletionScore(record),
  };
}
