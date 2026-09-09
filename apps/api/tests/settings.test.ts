import { expect, it } from "vitest";
import { normalizeSettings, nextDaily, generationSchema } from "../src/domain";
it("normalizes legacy settings and queued job snapshots without overriding explicit levels", () => {
  for (const [difficulty, engineeringLevel] of [["easy", "junior"], ["medium", "mid"], ["hard", "senior"]]) {
    expect(normalizeSettings({ difficulty }).engineeringLevel).toBe(engineeringLevel);
    expect(normalizeSettings({ difficulty, engineeringLevel: "intern" }).engineeringLevel).toBe("intern");
  }
  expect(normalizeSettings({}).engineeringLevel).toBe("mid");
  expect(generationSchema.safeParse({ engineeringLevel: "L9" }).success).toBe(false);
});
it("keeps wall-clock scheduling through DST and non-integral UTC offsets", () => {
  const settings = normalizeSettings({ timezone: "America/New_York", dailyMinutes: 540 });
  expect(nextDaily(settings, new Date("2026-03-07T15:00:00Z"))).toBe("2026-03-08T13:00:00.000Z");
  expect(nextDaily(settings, new Date("2026-10-31T15:00:00Z"))).toBe("2026-11-01T14:00:00.000Z");
  expect(nextDaily({ ...settings, timezone: "Asia/Kolkata" }, new Date("2026-03-07T15:00:00Z"))).toBe("2026-03-08T03:30:00.000Z");
});
