import { captureSchema, receiptSchema } from "./companion-contract";
import { z } from "zod";
import { Temporal } from "@js-temporal/polyfill";

export const MODEL_ID = "google/gemini-3.1-flash-lite";
export const engineeringLevelSchema = z.enum(["intern", "junior", "mid", "senior", "staff", "principal"]);
export const levelForDifficulty = (difficulty: string) => difficulty === "easy" ? "junior" : difficulty === "hard" ? "senior" : "mid";
export const settingsSchema = z.object({
  onboardingComplete: z.boolean().default(false),
  focus: z.string().trim().min(1).max(4000).default("System design"),
  engineeringLevel: engineeringLevelSchema.optional(),
  difficulty: z.enum(["easy", "medium", "hard"]).default("medium"),
  timezone: z
    .string()
    .refine((value) => {
      try {
        Temporal.Now.zonedDateTimeISO(value);
        return true;
      } catch {
        return false;
      }
    }, "Invalid timezone")
    .default("Europe/Prague"),
  dailyMinutes: z.number().int().min(0).max(1439).default(540),
  reminderEnabled: z.boolean().default(false),
  aiMode: z.enum(["managed", "byok"]).default("managed"),
  model: z.literal(MODEL_ID).default(MODEL_ID),
});
export type Settings = z.infer<typeof settingsSchema>;
export const challengeSchema = z.object({
  title: z.string().min(1).max(160),
  prompt: z.string().min(20).max(3000),
  topic: z.string().min(1).max(80),
});
export const questionSpecificationSchema = challengeSchema.extend({
  kind: z.enum(["explain", "design"]),
  targetSkill: z.string().min(1).max(160),
  constraints: z.array(z.string().min(1).max(300)).max(5),
  evaluationCriteria: z.array(z.string().min(1).max(3000)).min(1).max(6),
  ambiguityPolicy: z.string().min(1).max(300),
});
export const questionGenerationSchema = questionSpecificationSchema.omit({
  evaluationCriteria: true,
});
export const reflectionSchema = z.object({
  summary: z.string().min(1).max(1000),
  worked: z.array(z.string().max(300)).max(4),
  improve: z.string().min(1).max(1000),
  takeaway: z.string().min(1).max(1000),
  strengths: z.array(z.string().max(80)).max(4),
  gaps: z.array(z.string().max(80)).max(4),
});
export const exampleSchema = z.object({
  overview: z.string().min(1).max(3000),
  sections: z
    .array(
      z.object({ heading: z.string().max(100), body: z.string().max(4000) }),
    )
    .min(1)
    .max(8),
  tradeoffs: z.array(z.string().max(1000)).max(6),
  pitfalls: z.array(z.string().max(1000)).max(6),
});
export const answerSchema = z.object({
  answer: z.string().max(24000),
  revision: z.number().int().nonnegative(),
  receipts: z.array(receiptSchema).max(100).optional(),
});
export class Fault extends Error {
  constructor(
    public code: string,
    public status: number,
    message: string,
  ) {
    super(message);
  }
}
export function nextDaily(settings: Settings, now = new Date()): string {
  const current = Temporal.Instant.from(now.toISOString()).toZonedDateTimeISO(
    settings.timezone,
  );
  let candidate = current.with({
    hour: Math.floor(settings.dailyMinutes / 60),
    minute: settings.dailyMinutes % 60,
    second: 0,
    millisecond: 0,
    microsecond: 0,
    nanosecond: 0,
  });
  if (Temporal.ZonedDateTime.compare(candidate, current) <= 0)
    candidate = candidate.add({ days: 1 });
  return new Date(candidate.epochMilliseconds).toISOString();
}
export const timestamp = () => new Date().toISOString();
export const uuid = () => crypto.randomUUID();
export function requireCommand(value: string | undefined): string {
  if (!value || !z.string().uuid().safeParse(value).success)
    throw new Fault(
      "invalid_command",
      400,
      "A UUID Idempotency-Key is required.",
    );
  return value;
}
export function parseJSON<T>(text: string): T {
  return JSON.parse(text) as T;
}

export function normalizeSettings(value: unknown): Settings {
  const settings = settingsSchema.parse({ ...(value as object), model: MODEL_ID });
  return { ...settings, engineeringLevel: settings.engineeringLevel ?? levelForDifficulty(settings.difficulty) };
}
export const generationSchema = z.object({
  interviewStyle: z.enum(["quick", "standard", "in_depth"]).optional(),
  focus: z.string().trim().min(1).max(4000).optional(),
  kind: z.enum(["auto", "explain", "design"]).default("auto"),
  engineeringLevel: engineeringLevelSchema.optional(),
  difficulty: z.enum(["easy", "medium", "hard"]).optional(),
  replaceId: z.string().optional(),
  instruction: z.string().trim().max(1000).default(""),
  followUpId: z.string().optional(),
});
export const helpInputSchema = z.object({
  kind: z.enum([
    "hint",
    "check",
    "question",
    "outline",
    "example",
    "draft",
    "nudge",
    "guide",
    "starting_point",
    "alternative",
  ]),
  mode: z.enum(["coach", "guided"]),
  question: z.string().trim().max(2000).default(""),
  revision: z.number().int().nonnegative(),
  capture: captureSchema.optional(),
});
export const helpOutputSchema = z.object({
  body: z.string().min(1).max(6000),
  suggestedAnswer: z.string().min(1).max(16000).nullable(),
});
export const adoptionSchema = z.object({
  sourceId: z.string(),
  operation: z.enum(["append", "replace", "undo"]),
  revision: z.number().int().nonnegative(),
});

export function helpSchemaFor(kind: string) {
  return helpOutputSchema.extend({
    suggestedAnswer: kind === "draft" ? z.string().min(1).max(16000) : z.null(),
  });
}

export const reflectionOutputSchema = reflectionSchema.extend({
  summary: z.string().min(1).max(350),
  worked: z.array(z.string().max(300)).max(1),
  improve: z.string().min(1).max(500),
  takeaway: z.string().max(300),
});
