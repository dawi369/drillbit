import { z } from "zod";
export const companionUpdateSchema = z.object({
  revision: z.number().int().nonnegative(),
  operation: z.enum(["mode", "pause", "focus", "discussion"]),
  mode: z.enum(["solo", "coach", "guided"]).optional(),
  paused: z.boolean().optional(),
  text: z.string().trim().min(1).max(2000).optional(),
});
export const receiptSchema = z.object({
  id: z.string().uuid(),
  helpId: z.string(),
  disposition: z.enum(["uncertain", "shown", "dismissed", "superseded"]),
});
export const receiptsSchema = z.object({
  receipts: z.array(receiptSchema).max(100),
});
export const captureSchema = z.object({
  contextRevision: z.number().int().nonnegative(),
  modeEpoch: z.number().int().nonnegative(),
  cycle: z.string().min(1).max(128),
  digest: z.string().min(1).max(128),
  trigger: z.enum(["explicit", "guided_entry", "change", "pause"]),
});
export const interventionSchema = z.object({
  outcome: z.enum(["intervention", "no_intervention"]),
  body: z.string().max(240),
  suggestedFocus: z.string().max(180).nullable(),
  plan: z.array(z.string().max(180)).max(3),
  suggestedAnswer: z.null(),
});

export const coachInterventionSchema = interventionSchema.extend({
  suggestedFocus: z.null(),
  plan: z.array(z.string()).max(0),
});
export function interventionFor(kind: string) {
  return kind === "nudge" ? coachInterventionSchema : interventionSchema;
}
