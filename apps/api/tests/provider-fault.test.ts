import { expect, it } from "vitest";
import { providerFault } from "../src/ai";

const guardrail = '{"error":{"message":"0 endpoints out of 2 requested are available matching your guardrail restrictions and data policy.","code":404}}';
const credits = '{"error":{"message":"Insufficient credits. Add more using https://openrouter.ai/settings/credits","code":402}}';
const keyLimit = '{"error":{"message":"Key limit exceeded (monthly limit). Manage it using https://openrouter.ai/settings/keys","code":403}}';

it("names each managed-key misconfiguration and keeps it a reported 503", () => {
  expect(providerFault(402, credits, true)).toMatchObject({ code: "managed_out_of_credits", status: 503 });
  expect(providerFault(403, keyLimit, true)).toMatchObject({ code: "managed_budget_reached", status: 503 });
  expect(providerFault(404, guardrail, true)).toMatchObject({ code: "managed_policy_blocked", status: 503 });
  // A revoked managed key is ours to fix; the user must not be told to replace a key they never gave us.
  expect(providerFault(401, "", true)).toMatchObject({ code: "managed_key_rejected", status: 503 });
});

it("points BYOK users at their own key and stays out of the outage reports", () => {
  expect(providerFault(401, "", false)).toMatchObject({ code: "credential_invalid", status: 422 });
  expect(providerFault(402, credits, false)).toMatchObject({ code: "credential_out_of_credits", status: 422 });
  expect(providerFault(403, keyLimit, false)).toMatchObject({ code: "credential_limit_reached", status: 422 });
  expect(providerFault(404, guardrail, false)).toMatchObject({ code: "credential_policy_blocked", status: 422 });
});

it("treats anything else as a provider outage", () => {
  for (const status of [404, 429, 500, 502, 503]) expect(providerFault(status, '{"error":{"message":"No endpoints found"}}', true)).toMatchObject({ code: "provider_unavailable", status: 503 });
  expect(providerFault(403, '{"error":{"message":"Flagged by moderation"}}', false)).toMatchObject({ code: "provider_unavailable", status: 503 });
});
