import { z } from "zod";
export const concepts = [
  ["data-modeling", "Data modeling", "Data"],
  ["indexing", "Indexing & access patterns", "Data"],
  ["transactions", "Transactions", "Data"],
  ["consistency", "Consistency", "Data"],
  ["replication", "Replication", "Data"],
  ["partitioning", "Partitioning", "Data"],
  ["api-design", "API design", "Traffic & performance"],
  ["caching", "Caching", "Traffic & performance"],
  ["load-balancing", "Load balancing", "Traffic & performance"],
  ["rate-limiting", "Rate limiting", "Traffic & performance"],
  ["capacity-planning", "Capacity planning", "Traffic & performance"],
  ["queues", "Queues & streams", "Async & coordination"],
  ["retry-safety", "Retry safety & idempotency", "Async & coordination"],
  ["coordination", "Ordering & coordination", "Async & coordination"],
  ["scheduling", "Scheduling", "Async & coordination"],
  ["fault-tolerance", "Fault tolerance & recovery", "Reliability & operations"],
  ["backpressure", "Overload & backpressure", "Reliability & operations"],
  ["observability", "Observability", "Reliability & operations"],
  ["migration", "Deployment & migration", "Reliability & operations"],
  ["authorization", "Authentication & authorization", "System boundaries"],
  ["tenant-isolation", "Tenant isolation", "System boundaries"],
  ["data-lifecycle", "Data lifecycle & privacy", "System boundaries"],
  ["multi-region", "Multi-region design", "System boundaries"],
  ["cost-efficiency", "Cost efficiency", "System boundaries"],
].map(([id, label, category]) => ({
  id: id!,
  label: label!,
  category: category!,
  aliases: [] as string[],
}));
export const conceptId = z.enum(
  concepts.map((c) => c.id) as [string, ...string[]],
);
export const questionMetadata = z
  .object({
    scenario: z
      .string()
      .trim()
      .min(1)
      .max(70)
      .regex(/^\S+(?: \S+){0,2}$/, "Use a 1–3 word scenario"),
    primaryConceptId: conceptId,
    secondaryConceptIds: z.array(conceptId).max(2),
    tagEvidence: z
      .array(
        z.object({
          conceptId,
          requirementIndex: z.number().int().min(0).max(5),
        }),
      )
      .min(1)
      .max(3),
  })
  .superRefine((value, ctx) => {
    const ids = [value.primaryConceptId, ...value.secondaryConceptIds];
    if (new Set(ids).size !== ids.length)
      ctx.addIssue({
        code: "custom",
        message: "Concept tags must be distinct",
      });
    if (
      value.tagEvidence.length !== ids.length ||
      ids.some(
        (id) =>
          value.tagEvidence.filter((e) => e.conceptId === id).length !== 1,
      )
    )
      ctx.addIssue({
        code: "custom",
        message: "Each tag needs one visible requirement",
      });
  });
export const eligibilityInput = z.object({
  revision: z.number().int().nonnegative(),
  eligible: z.boolean(),
});
// Reserved for context engineering: no inferred observations are written by v1.
export const observationSchema = z.object({
  version: z.literal(1),
  attemptId: z.string(),
  conceptId,
  competency: z.enum([
    "requirements",
    "scale",
    "boundaries",
    "correctness",
    "tradeoffs",
    "failure",
    "evolution",
    "communication",
  ]),
  state: z.enum([
    "demonstrated",
    "developing",
    "needs_revisit",
    "not_observed",
  ]),
  text: z.string(),
  sourceTurnIds: z.array(z.string()),
  exposure: z.enum(["unassisted", "prompted", "example", "adopted", "unknown"]),
});

const definitions: Record<string, [string, string[]]> = {
  "data-modeling": [
    "Choose entities, relationships and data representations for stated access needs.",
    ["schema", "entities"],
  ],
  indexing: [
    "Choose access paths and explain read/write costs.",
    ["indexes", "query planning"],
  ],
  transactions: [
    "Preserve invariants across concurrent changes and transaction boundaries.",
    ["atomicity", "isolation"],
  ],
  consistency: [
    "Define what readers observe and justify allowed staleness.",
    ["eventual consistency", "linearizability"],
  ],
  replication: [
    "Copy data safely and reason about lag and failover.",
    ["replicas"],
  ],
  partitioning: [
    "Distribute data and load while handling skew and rebalancing.",
    ["sharding", "hotspots"],
  ],
  "api-design": [
    "Define service contracts, requests, responses and boundary behavior.",
    ["interfaces", "endpoints"],
  ],
  caching: [
    "Choose cache boundaries and explain invalidation and stale data behavior.",
    ["cache invalidation"],
  ],
  "load-balancing": [
    "Route traffic across capacity and handle unhealthy destinations.",
    ["routing"],
  ],
  "rate-limiting": [
    "Control request admission fairly under explicit limits.",
    ["quotas", "throttling"],
  ],
  "capacity-planning": [
    "Estimate demand, resource use and bottlenecks.",
    ["estimation", "throughput"],
  ],
  queues: [
    "Decouple work with messaging and explain delivery/consumer behavior.",
    ["messaging", "streams"],
  ],
  "retry-safety": [
    "Prevent unintended repeated effects after retries or ambiguous results.",
    ["idempotency", "deduplication"],
  ],
  coordination: [
    "Coordinate concurrent participants and ordering requirements.",
    ["locks", "consensus"],
  ],
  scheduling: [
    "Assign and trigger work at appropriate times across workers.",
    ["jobs", "timers"],
  ],
  "fault-tolerance": [
    "Maintain or recover required behavior after component failures.",
    ["recovery", "failover"],
  ],
  backpressure: [
    "Bound resource use and propagate overload without cascading failure.",
    ["overload", "admission control"],
  ],
  observability: [
    "Use operational signals to detect and diagnose relevant failures.",
    ["metrics", "tracing"],
  ],
  migration: [
    "Change live systems safely through rollout, compatibility and rollback.",
    ["deployment", "rollout"],
  ],
  authorization: [
    "Establish identity and enforce permitted actions at trust boundaries.",
    ["authentication", "permissions"],
  ],
  "tenant-isolation": [
    "Separate customer access and resource effects.",
    ["multi-tenancy"],
  ],
  "data-lifecycle": [
    "Handle retention, deletion and privacy across data copies.",
    ["retention", "privacy"],
  ],
  "multi-region": [
    "Place and coordinate systems across regions with explicit trade-offs.",
    ["geography"],
  ],
  "cost-efficiency": [
    "Compare resource cost against stated service requirements.",
    ["cost", "efficiency"],
  ],
};
for (const concept of concepts) {
  const [description, aliases] = definitions[concept.id]!;
  Object.assign(concept, { description, aliases });
}
