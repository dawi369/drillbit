import { z } from "../../apps/api/node_modules/zod";
import {
    captureSchema,
    companionUpdateSchema,
    interventionSchema,
    receiptsSchema,
} from "../../apps/api/src/companion-contract";
import {
    adoptionSchema,
    answerSchema,
    challengeSchema,
    engineeringLevelSchema,
    exampleSchema,
    generationSchema,
    helpInputSchema,
    helpOutputSchema,
    learningEvidenceSchema,
    practiceProfileSchema,
    questionSpecificationSchema,
    reflectionSchema,
    settingsSchema,
} from "../../apps/api/src/domain";
import { interviewInputSchema, interviewResultSchema, interviewStyleSchema } from "../../apps/api/src/interview";
import { guidanceModeSchema } from "../../apps/api/src/prompts/teaching";
import { conceptId, eligibilityInput, observationSchema } from "../../apps/api/src/taxonomy";
import { voiceDelegateSchema, voiceEventsSchema, voiceFragmentSchema, voiceStartSchema } from "../../apps/api/src/voice";
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
const interview = z.object({
  guidanceMode: guidanceModeSchema.optional(), style: interviewStyleSchema, prompt: z.string(), wrapUp: z.boolean(),
  turns: z.array(z.object({ id: z.string(), ordinal: z.number().int(), kind: z.enum(["answer","clarification","hint","example","continue","voice"]), prompt: z.string(), text: z.string(), createdAt: z.string(), jobId: z.string(), status: z.string(), error: z.string().nullable().optional(), partial: z.string().nullable().optional(), voice:z.array(voiceFragmentSchema).optional(), result: interviewResultSchema.nullable() })),
});
const challenge = challengeSchema.extend({
  questionId: z.string().optional(), scenario:z.string().optional(), primaryConceptId:conceptId.optional(), conceptIds:z.array(conceptId).optional(), selectionReason:z.string().optional(), constraints:z.array(z.string()).max(5).optional(),
  interviewStyle: interviewStyleSchema.optional(),
  guidanceMode: guidanceModeSchema.optional(),
  // Onboarding warm-up: excluded from progress, Recall, evidence and history.
  warmUp: z.boolean().optional(),
  interview: interview.optional(),
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
const libraryQuestion=z.object({id:z.string(),title:z.string(),prompt:z.string(),scenario:z.string(),engineeringLevel:engineeringLevelSchema,primaryConceptId:conceptId,conceptIds:z.array(conceptId).min(1).max(3),eligible:z.boolean(),eligibilityRevision:z.number().int(),lastActivity:z.string().optional(),attemptCount:z.number().int().optional()});
const recallCard=z.object({id:z.string(),sourceChallengeId:z.string(),conceptId,question:z.string(),answer:z.string(),dueAt:z.string(),intervalDays:z.number().int(),repetitions:z.number().int(),lapses:z.number().int(),createdAt:z.string(),updatedAt:z.string(),sourceTitle:z.string().optional(),sourceCompletedAt:z.string().optional(),evidence:learningEvidenceSchema.optional()});
const todayPlan=z.object({state:z.enum(["first_session","resume","review_due","question_ready","complete_today","prepare"]),completedTotal:z.number().int().nonnegative(),completedLastSevenDays:z.number().int().nonnegative(),completedToday:z.number().int().nonnegative(),dueRecallCount:z.number().int().nonnegative(),recommendedRecallCount:z.number().int().nonnegative(),estimatedRecallMinutes:z.number().int().nonnegative(),dailyGoalMinutes:z.union([z.literal(5),z.literal(10),z.literal(15),z.literal(20)])});
export const wire = {
  VoiceStart:voiceStartSchema, VoiceEvents:voiceEventsSchema, VoiceDelegate:voiceDelegateSchema,
  VoiceConnection:z.object({id:z.string(),sdp:z.string(),expiresAt:z.string()}),
  Taxonomy:z.object({version:z.literal(1),concepts:z.array(z.object({id:conceptId,label:z.string(),category:z.string(),aliases:z.array(z.string()),description:z.string().optional()}))}),
  LibraryQuestion:libraryQuestion,
  LibraryPage:z.object({questions:z.array(libraryQuestion),nextCursor:z.string().nullable()}),
  LibraryDetail:z.object({question:libraryQuestion,attempts:z.array(challenge),nextCursor:z.string().nullable()}),
  EligibilityInput:eligibilityInput,
  SkillObservation:observationSchema,
  LearningEvidence: learningEvidenceSchema.extend({sessionId:z.string(),at:z.string()}),
  AccountExport: z.object({version:z.number().int(),asOf:z.string(),settings:settingsSchema,sessions:z.array(challenge),questions:z.array(libraryQuestion),nextCursor:z.string().nullable()}),
  Coverage:z.object({concepts:z.array(z.object({conceptId,completedAttempts:z.number().int(),distinctQuestions:z.number().int(),lastPractised:z.string().nullable()}))}),
  RecallCard:recallCard,
  RecallDeck:z.object({cards:z.array(recallCard),dueCount:z.number().int()}),
  RecallReview:z.object({rating:z.enum(["again","got_it"]),responseMs:z.number().int().min(0).max(3_600_000).optional()}),
  RecallReviewResult:z.object({card:recallCard}),
  Companion: companion,
  CompanionUpdate: companionUpdateSchema,
  DeliveryInput: receiptsSchema,
  Intervention: interventionSchema,
  Settings: settingsSchema,
  PracticeProfile: practiceProfileSchema,
  PersonalizationPreview: z.object({text:z.string()}),
  HelpInput: helpInputSchema,
  HelpOutput: helpOutputSchema,
  AdoptionInput: adoptionSchema,
  InterviewInput: interviewInputSchema,
  InterviewState: interview,
  InterviewStreamSnapshot: z.object({ status: z.string(), text: z.string() }),
  QuestionStreamSnapshot: z.object({ status: z.string(), error: z.string().nullable(), title: z.string(), prompt: z.string() }),
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
  KeyInput: z.object({ key: z.string(), model: z.string().optional() }),
  Question: z.object({ question: z.string().max(4000) }),
  Credential: z.object({ suffix: z.string(), model: z.string() }),
  Bootstrap: z.object({
    practiceEpoch:z.string().optional(),
    account: z.object({ id: z.string(), status: z.string() }),
    settings: settingsSchema,
    todayPlan: todayPlan.optional(),
    challenge: challenge.nullable(),
    jobs: z.array(job),
    credential: z.object({ suffix: z.string(), model: z.string().nullable() }).nullable(),
    capabilities: z.object({
      automaticCompanion: z.boolean().optional(),
      managedAI: z.boolean(),
      voiceInterview: z.boolean(),
      voice: z.object({ available: z.boolean(), reason: z.string().optional(), checkedAt: z.string() }).optional(),
      developerTools: z.boolean().optional(),
    }),
  }),
  DailyQuestion: z.object({day:z.string(),challenge:challenge.optional(),job:job.nullable().optional()}),
  Generation: z.union([job, z.object({ challenge })]),
  ExampleOperation: z.union([job, z.object({ example: exampleSchema })]),
  HistoryPage: z.object({
    sessions: z.array(challenge),
    nextCursor: z.string().nullable(),
  }),
  Memory: z.object({
    evidence:z.array(learningEvidenceSchema.extend({sessionId:z.string(),at:z.string()})).optional(),
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
