import { z } from "zod";
import { questionGenerationSchema, type Settings } from "./domain";
import { concepts } from "./taxonomy";

type GenerationInput = { settings: Settings; guidanceMode?: string; instruction?: string; followUp?: unknown };

/** The question-writing context and strict schema; prompt evaluations use this to send exactly what production sends. */
export function generationRequest(input: GenerationInput, selection: { primaryConceptId: string; reason: string }, historicalSnapshot?: unknown) {
  // A mock round always opens with an open prompt the candidate has to scope, like a real one.
  const mock = input.guidanceMode === "mock_interview";
  const exploratory = mock || (["senior", "staff", "principal"].includes(input.settings.engineeringLevel ?? "")
    && input.guidanceMode !== "learn_together");
  // minutes is the round's time budget, set by the model; only Mock interview shows the clock. path is Guided's roadmap. opener is the interviewer's first line at Start.
  const roundLength = { minutes: z.number().int().min(10).max(60), path: z.array(z.string().trim().min(1).max(60)).min(3).max(5), opener: z.string().trim().min(1).max(240) };
  const schema = exploratory
    ? questionGenerationSchema.safeExtend({primaryConceptId:z.literal(selection.primaryConceptId),constraints:z.array(z.string().min(1).max(300)).max(0),...roundLength})
    : questionGenerationSchema.safeExtend({primaryConceptId:z.literal(selection.primaryConceptId),...roundLength});
  const context = {
    settings: input.settings,
    historicalSnapshot,
    kind: "design",
    selection,
    taxonomy: concepts,
    metadataInstructions: "Design a system-design problem centrally testing selection.primaryConceptId. Return that exact primaryConceptId and 0–2 distinct secondaryConceptIds from the taxonomy. scenario is a 1–3 word noun phrase. tagEvidence is the sole tag list: include the primary concept exactly once and at most two secondary concepts. Each entry has requirementIndex: 0 for prompt, or 1-based index into constraints. Concepts classify the problem, never introduce hidden grading requirements. roleTrack may change scenario vocabulary only; it must not change scope, difficulty, visible requirements or evaluation criteria. targetDate must not change the question. minutes is how long a real interviewer would give this one question in a round, 10–60, scaled to its scope and the level: a focused decision about 15, a full senior system design 35–45. path lists the 3–5 steps a strong answer works through for this question, in order, each a short imperative under 60 characters (for example \"Pin down what clients need\", \"Sketch the API\", \"Choose the storage\", \"Handle failures\"). Guided learners see it as their roadmap; it adds no requirement. opener is the interviewer's first line, said out loud when the candidate presses Start, under 240 characters: at most one short sentence that fits this person (their level, curriculumContext.objective or roleTrack; never their name or anything not supplied), then ONE concrete first decision from the first path step, answerable in a sentence (for example \"You've built a few systems, so let's skip the basics. A worker can crash at any point. What should a client be able to rely on?\"). It never reveals an answer, adds a requirement or repeats the prompt. " + (exploratory ? "This is an exploratory interview: constraints MUST be empty. Give one concrete design decision and only the initial context in the prompt. Leave negotiable parameters open for the interview conversation. Do not create hidden requirements or grade unstated limits." + (mock ? " This is a Mock interview opener: write the prompt the way an interviewer says it out loud, one to three sentences, with no scale numbers or requirement lists (for example \"Design a URL shortener like bit.ly.\"). The candidate scopes it by asking." : "") : "This is Guided or a lower-level interview: put useful concrete requirements in the prompt or visible constraints so the learner can start without negotiating every assumption."),
    instruction: input.instruction,
    followUp: input.followUp,
    curriculumContext: input.settings.learningPlan ? {
      objective: input.settings.learningPlan.objective,
      roleTrack: input.settings.learningPlan.roleTrack,
      // These influence scenario framing and session size, never hidden requirements or grading.
      dailyGoalMinutes: input.settings.learningPlan.dailyGoalMinutes,
    } : undefined,
  };
  return { context, schema };
}
