/**
 * Question markup is a small tag set the native app renders itself; it is never parsed as HTML.
 * Keep this list in sync with `QuestionMarkup` in apps/ios/Shared/Models.swift.
 */
export const QUESTION_TAGS = ["b", "i", "code", "pre"] as const;

const examples = [
  "Design the write path for a <b>link shortener</b> that never hands out the same short code twice. Codes look like <code>dbit.ly/k3X9a</code>. Walk through how you generate them and what happens when two requests race for the same code.",
  "An order service emits this event on every status change:<pre>{\n  \"orderId\": \"ord_812\",\n  \"status\": \"shipped\",\n  \"updatedAt\": \"2026-03-02T10:14:00Z\"\n}</pre>Design how a notifications service sends <i>exactly one</i> message per status change, even though the queue redelivers events.",
  "A profile cache is configured with <code>ttl = 300</code> seconds and sits in front of a database that handles <b>2,000 reads per second</b>. Decide what happens to the database when a popular profile expires and 500 requests miss at once.",
];

export function questionFormattingInstructions(enabled: boolean): string {
  if (!enabled) return "\n<question_formatting>Write title, prompt and constraints as plain text. Never use markup tags, Markdown, backticks or code fences.</question_formatting>";
  return `
<question_formatting>
The app renders a small tag set in the prompt and constraints. The title is always plain text.
- <b>…</b> for the one or two phrases carrying the core decision or a key number. Never a whole sentence.
- <i>…</i> for a nuance the reader must not miss, such as "exactly one" or "at least".
- <code>…</code> for identifiers, field names, endpoints, variable definitions and literal values.
- <pre>…</pre> for a short payload, schema or snippet (12 lines at most) that is easier to read than to describe. Pretty-print JSON with two-space indentation. Put it between sentences, never inside a list.
Use formatting only where it helps someone read the question faster; most sentences have none. No other tags, no Markdown, no backticks, no nesting. Write a literal <, > or & as &lt;, &gt; or &amp;.
Examples of well-formatted prompts:
${examples.map((example) => `<example>${example}</example>`).join("\n")}
</question_formatting>`;
}

/** Removes question markup, e.g. for places that show a plain preview. */
export function plainQuestion(text: string): string {
  return text
    .replace(/<\/?(?:b|i|code|pre)>/g, "")
    .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
}
