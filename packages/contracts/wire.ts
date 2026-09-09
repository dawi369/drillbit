import {
  captureSchema,
  companionUpdateSchema,
  receiptsSchema,
  interventionSchema,
} from "../../apps/api/src/companion-contract";
import { z } from "../../apps/api/node_modules/zod";
import {
  settingsSchema,
  engineeringLevelSchema,
  helpInputSchema,
  helpOutputSchema,
  adoptionSchema,
  generationSchema,
  questionSpecificationSchema,
  challengeSchema,
  reflectionSchema,
  exampleSchema,
  answerSchema,
} from "../../apps/api/src/domain";
const job = z
  .object({
    id: z.string(),
    kind: z.string(),
    status: z.enum(["pending", "running", "completed", "failed", "cancelled"]),
    error: z.string().nullable().optional(),
    challenge_id: z.string().nullable().optional(),
  })
  .loose();
const request = z.object({ id: z.string(), status: z.string() });
const companion = z.object({
  cycleConsumed: z.boolean().optional(),
  guidedStarted: z.boolean().optional(),
  revision: z.number().int(),
  mode: z.enum(["solo", "coach", "guided"]),
  modeEpoch: z.number().int(),
  paused: z.boolean(),
  selectedFocus: z.string().nullable(),
  decisions: z.array(z.object({ id: z.string(), text: z.string() })),
  automaticCount: z.number().int(),
  lastAutomaticAt: z.string().nullable(),
  digest: z.string(),
  cycle: z.string(),
});
const challenge = challengeSchema.extend({
  difficulty: z.enum(["easy", "medium", "hard"]).optional(),
  engineeringLevel: engineeringLevelSchema.optional(),
  id: z.string(),
  lifecycle: z.enum([
    "prepared",
    "ready",
    "in_progress",
    "completed",
    "skipped",
    "expired",
  ]),
  createdAt: z.string().optional(),
  completedAt: z.string().nullable().optional(),
  session: z
    .object({
      answer: z.string(),
      revision: z.number().int(),
      updated_at: z.string(),
    })
    .nullable()
    .optional(),
  turns: z
    .array(
      z
        .object({
          id: z.string(),
          role: z.string(),
          text: z.string(),
          state: z.string(),
        })
        .loose(),
    )
    .optional(),
  reflection: reflectionSchema.nullable().optional(),
  example: exampleSchema.nullable().optional(),
  companion: companion.optional(),
  automaticCompanion: z.boolean().optional(),
  coachRequest: request.nullable().optional(),
  help: z
    .array(
      z.object({
        id: z.string(),
        status: z.string(),
        kind: z.string(),
        revision: z.number().int(),
        capture: captureSchema.nullable().optional(),
        deliveries: z.array(z.string()).optional(),
        outcome: z.enum(["intervention", "no_intervention"]).optional(),
        suggestedFocus: z.string().nullable().optional(),
        plan: z.array(z.string()).optional(),
        body: z.string().optional(),
        suggestedAnswer: z.string().nullable().optional(),
      }),
    )
    .optional(),
  adoptions: z
    .array(
      z.object({
        id: z.string(),
        source_id: z.string(),
        operation: z.string(),
        revision: z.number().int(),
      }),
    )
    .optional(),
});
export const wire = {
  Companion: companion,
  CompanionUpdate: companionUpdateSchema,
  DeliveryInput: receiptsSchema,
  Intervention: interventionSchema,
  Settings: settingsSchema,
  HelpInput: helpInputSchema,
  HelpOutput: helpOutputSchema,
  AdoptionInput: adoptionSchema,
  PreparationInput: generationSchema,
  ChallengeContent: challengeSchema,
  QuestionSpecification: questionSpecificationSchema,
  Challenge: challenge,
  Reflection: reflectionSchema,
  Example: exampleSchema,
  DraftWrite: answerSchema,
  Job: job,
  RequestStatus: request,
  OK: z.object({ ok: z.boolean() }),
  Revision: z.object({ revision: z.number().int() }),
  InviteInput: z.object({ code: z.string() }),
  KeyInput: z.object({ key: z.string() }),
  Question: z.object({ question: z.string().max(4000) }),
  Credential: z.object({ suffix: z.string() }),
  Bootstrap: z.object({
    account: z.object({ id: z.string(), status: z.string() }),
    settings: settingsSchema,
    challenge: challenge.nullable(),
    jobs: z.array(job),
    credential: z.object({ suffix: z.string() }).nullable(),
    capabilities: z.object({
      automaticCompanion: z.boolean().optional(),
      managedAI: z.boolean(),
      voiceInterview: z.boolean(),
    }),
  }),
  Generation: z.union([job, z.object({ challenge })]),
  ExampleOperation: z.union([job, z.object({ example: exampleSchema })]),
  HistoryPage: z.object({
    sessions: z.array(challenge),
    nextCursor: z.string().nullable(),
  }),
  Memory: z.object({
    statistics: z.object({ completed: z.number().int().nonnegative(), lastSevenDays: z.number().int().nonnegative(), asOf: z.string() }).optional(),
    sessions: z.array(challenge),
    patterns: z.array(
      z.object({
        label: z.string(),
        kind: z.string(),
        sessionIds: z.array(z.string()),
      }),
    ),
  }),
  Device: z.object({
    id: z.string(),
    token: z.string(),
    expiresAt: z.string(),
  }),
  Widget: z.object({ challenge: challenge.nullable(), updatedAt: z.string() }),
  Deleting: z.object({ status: z.literal("deleting") }),
  Error: z
    .object({ error: z.object({ code: z.string(), message: z.string() }) })
    .loose(),
  StreamEvent: z.object({
    requestId: z.string(),
    text: z.string().optional(),
    message: z.string().optional(),
  }),
};
