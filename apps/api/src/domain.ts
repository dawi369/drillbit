import { Temporal } from "@js-temporal/polyfill";
import { z } from "zod";
import { captureSchema, receiptSchema } from "./companion-contract";
import { guidanceModeSchema } from "./prompts/teaching";
import { conceptId, questionMetadata } from "./taxonomy";

export const MODEL_ID = "openai/gpt-6-luna";
export const engineeringLevelSchema = z.enum(["intern", "junior", "mid", "senior", "staff", "principal"]);
export const levelForDifficulty = (difficulty: string) => difficulty === "easy" ? "junior" : difficulty === "hard" ? "senior" : "mid";
/** A mock round's time budget; the generator sets `minutes`, and older or pooled questions fall back by level. */
export function roundMinutes(data: { minutes?: unknown; engineeringLevel?: unknown }): number {
  if (typeof data.minutes === "number") return data.minutes;
  return ({ intern: 20, junior: 25, mid: 30, senior: 35, staff: 45, principal: 45 } as Record<string, number>)[String(data.engineeringLevel)] ?? 30;
}
export function roundTiming(data: { minutes?: unknown; engineeringLevel?: unknown; startedAt?: unknown }, fallbackStart: string, now = Date.now()) {
  const started = Date.parse(typeof data.startedAt === "string" ? data.startedAt : fallbackStart);
  return { limitMinutes: roundMinutes(data), elapsedMinutes: Math.max(0, Math.floor((now - started) / 60000)) };
}
export const practiceProfileSchema = z.object({
  goals: z.string().trim().max(600).default(""),
  background: z.string().trim().max(600).default(""),
  preferences: z.string().trim().max(600).default(""),
});
export const learningPlanSchema = z.object({
  version: z.literal(1).default(1),
  objective: z.enum(["interview", "learn", "stay_sharp"]),
  roleTrack: z.enum(["general", "backend", "frontend", "full_stack", "platform", "data", "mobile"]),
  weakAreas: z.array(z.enum(["data", "traffic", "async", "reliability", "boundaries"])).max(3),
  dailyGoalMinutes: z.union([z.literal(5), z.literal(10), z.literal(15), z.literal(20)]),
  targetDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
});
export type LearningPlan = z.infer<typeof learningPlanSchema>;
export const defaultLearningPlan = (): LearningPlan => ({
  version: 1, objective: "learn", roleTrack: "general", weakAreas: [], dailyGoalMinutes: 10,
});
export const settingsSchema = z.object({
  practiceProfile: practiceProfileSchema.optional(),
  learningPlan: learningPlanSchema.optional(),
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
  model: z.enum([MODEL_ID, "google/gemini-3.1-flash-lite", "google/gemini-2.5-flash-lite"]).default(MODEL_ID),
  // Absent means on; optional so older clients never reset it.
  questionFormatting: z.boolean().optional(),
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
}).extend({scenario:questionMetadata.shape.scenario,primaryConceptId:conceptId,tagEvidence:questionMetadata.shape.tagEvidence}).superRefine((value,ctx)=> {
 const ids=value.tagEvidence.map(e=>e.conceptId);
 if(new Set(ids).size!==ids.length||!ids.includes(value.primaryConceptId))ctx.addIssue({code:"custom",message:"Include the primary concept exactly once and at most two distinct secondary concepts"});
 if(value.tagEvidence.some(e=>e.requirementIndex>value.constraints.length))ctx.addIssue({code:"custom",message:"Tag reference does not exist"});
});
export const learningEvidenceSchema = z.object({
  conceptId,
  observation: z.string().min(1).max(300),
  quote: z.string().min(1).max(500),
  signal: z.enum(["demonstrated", "needs_practice"]),
  assistance: z.enum(["assisted", "unknown"]),
  sourceTurnId: z.string().optional(),
});
export const lessonSchema = z.object({
  learned: z.array(z.string().min(1).max(160)).max(3),
  tryAlone: z.string().min(1).max(300),
});
export const debriefSchema = z.object({
  verdict: z.enum(["pass", "borderline", "not_yet"]),
  reason: z.string().min(1).max(300),
  signals: z.array(z.object({
    area: z.enum(["requirements", "design", "trade_offs", "communication"]),
    rating: z.enum(["strong", "mixed", "weak", "not_shown"]),
    note: z.string().max(200),
  })).max(4),
  toPass: z.string().max(300),
});
export const reflectionSchema = z.object({
  evidence: z.array(learningEvidenceSchema).max(3).optional(),
  nextExercise: z.string().min(1).max(400).optional(),
  summary: z.string().min(1).max(1000),
  worked: z.array(z.string().max(300)).max(4),
  improve: z.string().max(1000),
  takeaway: z.string().min(1).max(1000),
  strengths: z.array(z.string().max(80)).max(4),
  gaps: z.array(z.string().max(80)).max(4),
  // Each session style ends differently; absent on reflections written before endings existed.
  guidanceMode: guidanceModeSchema.optional(),
  lesson: lessonSchema.optional(),
  debrief: debriefSchema.optional(),
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
  return { ...settings, focus: "System design", engineeringLevel: settings.engineeringLevel ?? levelForDifficulty(settings.difficulty) };
}
export function validateLearningPlanDate(settings: Settings, now = new Date()) {
  const plan = settings.learningPlan;
  if (!plan?.targetDate) return;
  if (plan.objective !== "interview")
    throw new Fault("invalid_target_date", 400, "An interview date requires the interview goal.");
  const today = Temporal.Instant.from(now.toISOString()).toZonedDateTimeISO(settings.timezone).toPlainDate();
  if (Temporal.PlainDate.compare(Temporal.PlainDate.from(plan.targetDate), today) < 0)
    throw new Fault("invalid_target_date", 400, "Choose today or a future interview date.");
}
export const generationSchema = z.object({
  guidanceMode: guidanceModeSchema.optional(),
  primaryConceptId: conceptId.optional(),
  interviewStyle: z.enum(["quick", "standard", "in_depth"]).optional(),
  focus: z.string().trim().min(1).max(4000).optional(),
  kind: z.enum(["auto", "explain", "design"]).default("auto"),
  engineeringLevel: engineeringLevelSchema.optional(),
  difficulty: z.enum(["easy", "medium", "hard"]).optional(),
  replaceId: z.string().optional(),
  instruction: z.string().trim().max(1000).default(""),
  followUpId: z.string().optional(),
  // Onboarding warm-up: a real generated interview that never counts as practice.
  warmUp: z.boolean().optional(),
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

export const reflectionOutputSchema = reflectionSchema.omit({ guidanceMode: true, lesson: true, debrief: true }).extend({
  // Attribution is derived from saved answer turns after inference. It is not
  // model output, and optional properties violate Luna's strict JSON schema.
  evidence: z.array(learningEvidenceSchema.omit({ sourceTurnId: true })).max(2),
  nextExercise: z.string().min(1).max(400),
  strengths: z.array(z.string().max(80)).max(2),
  gaps: z.array(z.string().max(80)).max(2),
  summary: z.string().min(1).max(350),
  worked: z.array(z.string().max(300)).max(1),
  improve: z.string().max(500),
  takeaway: z.string().max(300),
});
/** The ending's extra part is required model output for its mode, so strict schemas stay free of optional fields. */
export function reflectionOutputFor(mode: string) {
  if (mode === "learn_together") return reflectionOutputSchema.extend({ lesson: lessonSchema });
  if (mode === "mock_interview") return reflectionOutputSchema.extend({ debrief: debriefSchema.extend({ signals: debriefSchema.shape.signals.length(4) }) });
  return reflectionOutputSchema;
}
