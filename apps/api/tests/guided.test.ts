import { expect, it } from "vitest";
import { interviewSchemaFor, revisedGuidedPath } from "../src/interview";

const previous = { steps: ["Pin down the promise", "Sketch the lifecycle", "Handle failures", "Make retries safe"], current: 2 };

it("keeps the steps already done when the roadmap is redrawn", () => {
  const revised = revisedGuidedPath(previous, ["Something else", "Also changed", "Add a dead-letter queue", "Alert on backlog"]);
  expect(revised).toEqual(["Pin down the promise", "Sketch the lifecycle", "Add a dead-letter queue", "Alert on backlog"]);
});

it("ignores a missing, unchanged, too-short or done-only roadmap", () => {
  expect(revisedGuidedPath(previous, undefined)).toBeUndefined();
  expect(revisedGuidedPath(undefined, ["A", "B"])).toBeUndefined();
  expect(revisedGuidedPath(previous, previous.steps)).toBeUndefined();
  expect(revisedGuidedPath(previous, ["A", "B"])).toBeUndefined();
});

it("caps a redrawn roadmap at five steps", () => {
  const revised = revisedGuidedPath({ steps: ["One", "Two", "Three"], current: 1 }, ["x", "a", "b", "c", "d", "e"]);
  expect(revised).toEqual(["One", "a", "b", "c", "d"]);
});

it("accepts covered and a revised path on follow-ups", () => {
  const parsed = interviewSchemaFor("answer").parse({ outcome: "follow_up", text: "That covers it.", covered: true, path: ["A", "B", "C"] });
  expect(parsed.covered).toBe(true);
  expect(parsed.path).toEqual(["A", "B", "C"]);
});
