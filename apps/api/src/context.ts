/** Preserve current user work; trim only older context. This is a character budget, not a tokenizer estimate. */
export function boundedContext(input: unknown, limit = 40000): unknown {
  const source = input as Record<string, unknown>;
  const result = { ...source };
  if (Array.isArray(result.interview)) result.interview = [...result.interview];
  else if (result.interview && typeof result.interview === "object") {
    const interview = result.interview as Record<string, unknown>;
    result.interview = { ...interview, turns: Array.isArray(interview.turns) ? [...interview.turns] : [] };
  }
  if ("example" in result) {
    result.exampleViewed = Boolean(result.example);
    delete result.example;
  }
  if (Array.isArray(result.help)) {
    result.assistance = result.help.reduce(
      (counts: Record<string, number>, h: any) => {
        const key = String(h.kind) + (h.body ? ":generated" : ":" + h.status);
        counts[key] = (counts[key] ?? 0) + 1;
        return counts;
      },
      {},
    );
    result.help = result.help
      .filter((h: any) => h.body)
      .slice(-3)
      .map((h: any) => ({
        id: h.id,
        kind: h.kind,
        body: String(h.body).slice(0, 1200),
        deliveries: h.deliveries ?? ["unknown"],
      }));
  }
  if (Array.isArray(result.adoptions)) {
    result.adoptionCount = result.adoptions.length;
    result.adoptions = result.adoptions.slice(-5);
  }
  if (result.companion && typeof result.companion === "object") {
    const companion = result.companion as Record<string, unknown>;
    result.companion = {
      ...companion,
      decisions: Array.isArray(companion.decisions)
        ? companion.decisions.slice(-6)
        : [],
    };
  }
  for (const key of ["turns", "recent"]) {
    if (Array.isArray(result[key]))
      result[key] = [...(result[key] as unknown[])];
  }
  if (Array.isArray(result.turns)) result.turns = result.turns.slice(-6);
  while (JSON.stringify(result).length > limit) {
    const interview = result.interview as { turns?: unknown[] } | undefined;
    const history = Array.isArray(result.interview) ? result.interview : interview?.turns;
    if (history && history.length > 1) {
      history.shift();
      result.omittedInterviewTurns = Number(result.omittedInterviewTurns ?? 0) + 1;
      continue;
    }
    if (Array.isArray(result.recent) && result.recent.length) {
      result.recent.pop();
      continue;
    }
    if (Array.isArray(result.turns) && result.turns.length) {
      result.turns.shift();
      continue;
    }
    if (Array.isArray(result.help) && result.help.length) {
      result.help.shift();
      continue;
    }
    const companion = result.companion as { decisions?: unknown[] } | undefined;
    if (companion?.decisions && companion.decisions.length > 1) {
      companion.decisions.shift();
      continue;
    }
    if (Array.isArray(result.adoptions) && result.adoptions.length) {
      result.adoptions.shift();
      continue;
    }
    if (
      result.question &&
      typeof result.question === "object" &&
      "evaluationCriteria" in result.question
    ) {
      const { evaluationCriteria, ...question } = result.question as Record<
        string,
        unknown
      >;
      result.question = question;
      continue;
    }
    throw new Error("Current context exceeds the supported input size");
  }
  return result;
}

function escapeXML(value: string): string {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&apos;");
}
/** Data never becomes markup, even when a draft contains closing tags. */
export function xmlContext(input: unknown): string {
  function field(key: string, value: unknown): string {
    const name = /^[A-Za-z][A-Za-z0-9_]*$/.test(key) ? key : "field";
    const body = value == null ? "" : Array.isArray(value) ? value.map(item => field("item", item)).join("")
      : typeof value === "object" ? Object.entries(value).map(([k,v]) => field(k,v)).join("") : escapeXML(String(value));
    return `<${name}>${body}</${name}>`;
  }
  return field("practice_context", boundedContext(input));
}
