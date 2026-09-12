import { z } from "../apps/api/node_modules/zod";
import { wire } from "../packages/contracts/wire";
import { writeFileSync } from "node:fs";
const definitions = Object.fromEntries(
  Object.entries(wire).map(([name, schema]) => [name, z.toJSONSchema(schema)]),
);
const operations: [string, string, string, string?][] = [
  ["post","challenges/{id}/voice","Start a voice session without submitting the typed draft","VoiceStart"],
  ["post","challenges/{id}/voice/{voice}/events","Persist idempotent voice fragments and close receipts","VoiceEvents"],
  ["post","challenges/{id}/voice/{voice}/delegate","Request technical guidance for a live session","VoiceDelegate"],
  ["get", "account/export", "Export paginated account practice data without credentials"],
  ["get","taxonomy","Get the versioned system-design concept vocabulary"],
  ["get","library","Search and filter the account question library"],
  ["get","library/coverage","Count completed practice by concept without inferring ability"],
  ["get","questions/{id}","Read a question and paginated attempts"],
  ["put","questions/{id}/eligibility","Update question-pool eligibility with revision and idempotency","EligibilityInput"],
  ["post","questions/{id}/start","Start a fresh attempt for an immutable question"],
  ["post", "challenges/{id}/interview", "Commit an answer or request clarification/help without advancing the answer", "InterviewInput"],
  ["post", "challenges/{id}/interview/{turn}/retry", "Retry a failed interviewer response without resubmitting the answer"],
  [
    "put",
    "challenges/{id}/companion",
    "Update revision-checked companion context",
    "CompanionUpdate",
  ],
  [
    "post",
    "challenges/{id}/deliveries",
    "Record idempotent delivery receipts",
    "DeliveryInput",
  ],
  ["get", "bootstrap", "Get account, settings, active challenge and jobs"],
  ["post", "invite", "Redeem a single-use invitation", "InviteInput"],
  ["put", "settings", "Update practice preferences", "Settings"],
  [
    "post",
    "challenges",
    "Get active challenge or request generation",
    "PreparationInput",
  ],
  ["get", "challenges/{id}", "Read challenge, draft and assistance"],
  [
    "post",
    "challenges/{id}/help",
    "Request explicit durable help",
    "HelpInput",
  ],
  [
    "post",
    "challenges/{id}/adopt",
    "Insert or undo a revision-checked suggested draft",
    "AdoptionInput",
  ],
  ["post", "jobs/{id}/cancel", "Stop help; completed results are preserved"],
  ["post", "challenges/{id}/start", "Start a ready challenge"],
  [
    "put",
    "challenges/{id}/draft",
    "Save a revision-checked draft",
    "DraftWrite",
  ],
  [
    "post",
    "challenges/{id}/complete",
    "Complete once with final answer",
    "DraftWrite",
  ],
  ["post", "challenges/{id}/skip", "Skip active challenge"],
  ["post", "challenges/{id}/coach", "Stream coach SSE", "Question"],
  ["post", "challenges/{id}/example", "Request durable example generation"],
  ["delete", "challenges/{id}", "Delete session and learning evidence"],
  ["get", "sessions", "Search paginated completed sessions"],
  ["get", "memory", "Recent history and evidence-backed patterns"],
  ["get", "jobs/{id}", "Read durable operation status"],
  ["post", "jobs/{id}/retry", "Retry a failed operation"],
  ["get", "requests/{id}", "Read coach request status"],
  ["post", "requests/{id}/cancel", "Cancel a streaming request"],
  [
    "put",
    "credential",
    "Validate and replace encrypted OpenRouter key",
    "KeyInput",
  ],
  ["delete", "credential", "Remove key and cancel dependent jobs"],
  ["post", "devices", "Register a revocable widget credential"],
  ["delete", "devices/{id}", "Revoke widget credential"],
  ["delete", "account", "Disable and durably delete account"],
  ["get", "widget", "Read minimal widget snapshot using device token"],
];
const responseNames: Record<string, string> = {
  "get taxonomy":"Taxonomy", "get library":"LibraryPage", "get library/coverage":"Coverage", "get questions/{id}":"LibraryDetail", "put questions/{id}/eligibility":"LibraryQuestion", "post questions/{id}/start":"Challenge",
  "post challenges/{id}/interview": "InterviewState",
  "post challenges/{id}/interview/{turn}/retry": "InterviewState",
  "put challenges/{id}/companion": "Companion",
  "post challenges/{id}/deliveries": "OK",
  "post challenges/{id}/help": "Job",
  "post challenges/{id}/adopt": "Challenge",
  "post jobs/{id}/cancel": "OK",
  "get bootstrap": "Bootstrap",
  "post invite": "OK",
  "put settings": "Settings",
  "post challenges": "Generation",
  "get challenges/{id}": "Challenge",
  "post challenges/{id}/start": "Challenge",
  "put challenges/{id}/draft": "Revision",
  "post challenges/{id}/complete": "Challenge",
  "post challenges/{id}/skip": "OK",
  "post challenges/{id}/example": "ExampleOperation",
  "delete challenges/{id}": "OK",
  "get memory": "Memory",
  "get account/export": "AccountExport",
  "get sessions": "HistoryPage",
  "get jobs/{id}": "Job",
  "post jobs/{id}/retry": "Job",
  "get requests/{id}": "RequestStatus",
  "post requests/{id}/cancel": "OK",
  "put credential": "Credential",
  "delete credential": "OK",
  "post devices": "Device",
  "delete devices/{id}": "OK",
  "delete account": "Deleting",
  "get widget": "Widget",
};
const idempotent = new Set([
  "put questions/{id}/eligibility", "post questions/{id}/start",
  "post challenges/{id}/interview",
  "post challenges/{id}/interview/{turn}/retry",
  "put challenges/{id}/companion",
  "post challenges/{id}/help",
  "post challenges/{id}/adopt",
  "post challenges",
  "put challenges/{id}/draft",
  "post challenges/{id}/complete",
  "post challenges/{id}/coach",
  "post challenges/{id}/example",
  "post jobs/{id}/retry",
  "delete account",
]);
const json = (name: string) => ({
  "application/json": { schema: { $ref: "#/components/schemas/" + name } },
});
const paths: Record<string, Record<string, unknown>> = {};
for (const [method, path, summary, schema] of operations) {
  const full = "/v1/" + path;
  paths[full] ??= {};
  paths[full][method] = {
    summary,
    operationId: method + "_" + path.replace(/[^a-z]/g, "_"),
    parameters: [
      ...(path.includes("{turn}") ? [{ name: "turn", in: "path", required: true, schema: { type: "string" } }] : []),
      ...(["library","questions/{id}"].includes(path) ? (path === "library" ? ["cursor","q","concepts","level","since","skipped"] : ["cursor"]).map(name=>({name,in:"query",schema:{type:"string"}})) : []),
      ...(path === "account/export" ? [{name:"cursor",in:"query",schema:{type:"string"}}] : []),
      ...(path === "sessions"
        ? ["cursor", "q"].map((name) => ({
            name,
            in: "query",
            schema: { type: "string" },
          }))
        : []),
      ...(path.includes("{id}")
        ? [
            {
              name: "id",
              in: "path",
              required: true,
              schema: { type: "string" },
            },
          ]
        : []),
      ...(idempotent.has(method + " " + path)
        ? [
            {
              name: "Idempotency-Key",
              required: true,
              in: "header",
              description:
                "Required for generation, draft writes, completion, assistance, retries and deletion of an account.",
              schema: { type: "string", format: "uuid" },
            },
          ]
        : []),
    ],
    ...(schema
      ? {
          requestBody: {
            required: true,
            content: {
              "application/json": {
                schema: { $ref: "#/components/schemas/" + schema },
              },
            },
          },
        }
      : {}),
    responses: {
      ...(path.endsWith("/coach")
        ? {
            "200": {
              description:
                "SSE events: started, delta, completed, failed. Partial output is never authoritative. requestId matches Idempotency-Key.",
              content: { "text/event-stream": { schema: { type: "string" } } },
            },
          }
        : {
            "200": {
              description: "Successful operation",
              content: json(responseNames[method + " " + path]),
            },
          }),
      ...(idempotent.has(method + " " + path) && !path.endsWith("/coach")
        ? {
            "202": {
              description: "Durable operation accepted",
              content: json(responseNames[method + " " + path]),
            },
          }
        : {}),
      "400": { description: "Invalid input", content: json("Error") },
      "403": {
        description: "Invite required or account unavailable",
        content: json("Error"),
      },
      "404": { description: "Not found or not owned", content: json("Error") },
      "401": { description: "Authentication required", content: json("Error") },
      "409": {
        description: "Revision or lifecycle conflict",
        content: json("Error"),
      },
      "422": {
        description: "Invalid invitation or provider credential",
        content: json("Error"),
      },
      "503": {
        description: "Provider temporarily unavailable",
        content: json("Error"),
      },
      "429": { description: "Usage limit reached", content: json("Error") },
    },
  };
}
paths["/v1/challenges/{id}/interview/{turn}/stream"] = {
  get: {
    summary: "Subscribe to persisted interviewer text snapshots without starting another inference",
    parameters: [{name:"id",in:"path",required:true,schema:{type:"string"}},{name:"turn",in:"path",required:true,schema:{type:"string"}}],
    responses: {"200":{description:"SSE snapshot events with JSON text and job status. Partial text is provisional until completed; reconnect by resubscribing.",content:{"text/event-stream":{schema:{type:"string"}}}}}
  }
};
writeFileSync(
  "packages/contracts/openapi.json",
  JSON.stringify(
    {
      openapi: "3.1.0",
      info: { title: "Drillbit API", version: "1.0.0" },
      security: [{ bearerAuth: [] }],
      paths,
      components: {
        securitySchemes: { bearerAuth: { type: "http", scheme: "bearer" } },
        schemas: definitions,
      },
    },
    null,
    2,
  ) + "\n",
);
