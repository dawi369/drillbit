import { expect, it } from "vitest";
import { normalizeSettings, nextDaily, generationSchema, settingsSchema, validateLearningPlanDate } from "../src/domain";
it("normalizes legacy settings and queued job snapshots without overriding explicit levels", () => {
  for (const [difficulty, engineeringLevel] of [["easy", "junior"], ["medium", "mid"], ["hard", "senior"]]) {
    expect(normalizeSettings({ difficulty }).engineeringLevel).toBe(engineeringLevel);
    expect(normalizeSettings({ difficulty, engineeringLevel: "intern" }).engineeringLevel).toBe("intern");
  }
  expect(normalizeSettings({}).engineeringLevel).toBe("mid");
  expect(generationSchema.safeParse({ engineeringLevel: "L9" }).success).toBe(false);
});
it("validates structured learning plans without manufacturing one for existing accounts", () => {
  expect(normalizeSettings({}).learningPlan).toBeUndefined();
  const plan = {version:1 as const,objective:"interview" as const,roleTrack:"backend" as const,weakAreas:["data","async"] as const,dailyGoalMinutes:10 as const,targetDate:"2026-09-18"};
  const settings = settingsSchema.parse({timezone:"Europe/Prague",learningPlan:plan});
  expect(settings.learningPlan).toEqual(plan);
  expect(settingsSchema.safeParse({learningPlan:{...plan,weakAreas:["data","traffic","async","reliability"]}}).success).toBe(false);
  expect(() => validateLearningPlanDate({...settings,learningPlan:{...plan,targetDate:"2026-09-17"}},new Date("2026-09-18T10:00:00Z"))).toThrow();
});
it("accepts every supported learning-plan role, objective, level and daily commitment",()=>{
 for(const objective of ["interview","learn","stay_sharp"])
  for(const roleTrack of ["general","backend","frontend","full_stack","platform","data","mobile"])
   for(const engineeringLevel of ["intern","junior","mid","senior","staff","principal"])
    for(const dailyGoalMinutes of [5,10,15,20])
     expect(settingsSchema.safeParse({engineeringLevel,learningPlan:{version:1,objective,roleTrack,weakAreas:["data","async","reliability"],dailyGoalMinutes,...(objective === "interview" ? {targetDate:"2099-01-01"} : {})}}).success).toBe(true);
});
it("keeps wall-clock scheduling through DST and non-integral UTC offsets", () => {
  const settings = normalizeSettings({ timezone: "America/New_York", dailyMinutes: 540 });
  expect(nextDaily(settings, new Date("2026-03-07T15:00:00Z"))).toBe("2026-03-08T13:00:00.000Z");
  expect(nextDaily(settings, new Date("2026-10-31T15:00:00Z"))).toBe("2026-11-01T14:00:00.000Z");
  expect(nextDaily({ ...settings, timezone: "Asia/Kolkata" }, new Date("2026-03-07T15:00:00Z"))).toBe("2026-03-08T03:30:00.000Z");
});
