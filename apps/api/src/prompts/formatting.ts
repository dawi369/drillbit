/**
 * Question markup is a small tag set the native app renders itself; it is never parsed as HTML.
 * Keep this list in sync with `QuestionMarkup` in apps/ios/Shared/Models.swift.
 */
export const QUESTION_TAGS = ["b", "i", "code", "pre"] as const;

const examples = [
  "Design the write path for a <b>link shortener</b>.\n\n• Codes look like <code>dbit.ly/k3X9a</code>\n• About 50 million new links a month\n• A code is never handed out twice\n\nHow do you generate codes, and what happens when two requests race for the same one?",
  "An order service emits this event on every status change:<pre>{\n  \"orderId\": \"ord_812\",\n  \"status\": \"shipped\",\n  \"updatedAt\": \"2026-03-02T10:14:00Z\"\n}</pre>\n\nHow does a notifications service send <i>exactly one</i> message per status change, even though the queue redelivers events?",
  "A profile cache sits in front of your database.\n\n• Entries live for <code>ttl = 300</code> seconds\n• The database handles <b>2,000 reads per second</b>\n• A popular profile expires and 500 requests miss at once\n\nWhat happens to the database, and how do you protect it?",
];

// Plain-text layout, so it applies with formatting on or off; the app renders paragraphs, "• " lines and the closing ask.
const structure = `
<question_structure>
Lay the prompt out for quick reading. Open with one or two sentences of scenario. When the candidate needs key facts (users, scale, limits, existing pieces), give two to four of them, each on its own line starting with "• ". End with the ask on its own line: one sentence naming the decision. Separate these parts with a blank line. No headings. A Mock interview opener is the exception: one short paragraph, no bullets.
</question_structure>`;

export function questionFormattingInstructions(enabled: boolean): string {
  if (!enabled) return `${structure}\n<question_formatting>Write title, prompt and constraints as plain text. Never use markup tags, Markdown, backticks or code fences.</question_formatting>`;
  return `${structure}
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
