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

// Plain-text layout, so it applies with formatting on or off; the app renders paragraphs, "• " lines (the Key facts block) and the closing ask.
const defaultStructure = `
<question_structure>
Lay the prompt out for quick reading. Open with one or two sentences of scenario. Then, when the decision turns on them, two to four key facts, each on its own line starting with "• ": the users, scale, limits or existing pieces the answer depends on. One fact per line, under 80 characters, stated plainly with the number where it matters. A key fact is never a hint or the scenario restated, and constraints never repeat a key fact. End with the ask on its own line: one sentence naming the decision. Separate these parts with a blank line. No headings. Exploratory prompts keep key facts to fixed context (who uses it, what already exists) and leave numbers and limits for the candidate to ask about.
</question_structure>`;

// A Mock interview opens the way a real interviewer speaks: no key facts, the candidate scopes it by asking.
const mockStructure = `
<question_structure>
This prompt is a Mock interview opener. Write it the way an interviewer says it out loud: one short paragraph of scenario (one to three sentences), a blank line, then the ask on its own line as one question. No "• " lines, no lists of facts, numbers, limits or requirements; the candidate scopes the problem by asking. No headings.
</question_structure>`;

export function questionFormattingInstructions(enabled: boolean, mock = false): string {
  const structure = mock ? mockStructure : defaultStructure;
  if (!enabled) return `${structure}\n<question_formatting>Write title, prompt and constraints as plain text. Never use markup tags, Markdown, backticks or code fences.</question_formatting>`;
  return `${structure}
<question_formatting>
The app renders a small tag set in the prompt and constraints. The title is always plain text.
- <b>…</b> for the one or two phrases carrying the core decision or a key number. Never a whole sentence.
- <i>…</i> for a nuance the reader must not miss, such as "exactly one" or "at least".
- <code>…</code> for identifiers, field names, endpoints, variable definitions and literal values.
- <pre>…</pre> for a short payload, schema or snippet (12 lines at most) that is easier to read than to describe. Pretty-print JSON with two-space indentation. Put it between sentences, never inside a list.
Use formatting only where it helps someone read the question faster; most sentences have none. These four are the only tags that exist: never invent one, and never wrap a payload in a tag named after it; a payload goes in <pre>. No Markdown, no backticks, no nesting. Write a literal <, > or & as &lt;, &gt; or &amp;.
Examples of well-formatted prompts:
${examples.map((example) => `<example>${example}</example>`).join("\n")}
</question_formatting>`;
}

/** Removes question markup, e.g. for places that show a plain preview. */
/**
 * Models sometimes invent a tag (`<practice>{…}</practice>`, `<payload>…</payload>`). The app only knows
 * QUESTION_TAGS, so anything else is folded into them: a block-shaped body (several lines, or JSON) becomes
 * <pre>, otherwise the tag is dropped and its text kept. Tolerates an unclosed tag at the end of streaming text.
 */
export function normalizeQuestionMarkup(text: string): string {
  const known = new Set<string>(QUESTION_TAGS);
  return text
    .replace(/<([a-zA-Z][\w-]*)>([\s\S]*?)<\/\1>/g, (whole, tag: string, body: string) => {
      if (known.has(tag)) return whole;
      const block = body.includes("\n") || /^\s*[\[{]/.test(body);
      return block ? `<pre>${body.trim()}</pre>` : body;
    })
    .replace(/<\/?([a-zA-Z][\w-]*)>/g, (whole, tag: string) => (known.has(tag) ? whole : ""));
}

export function plainQuestion(text: string): string {
  return text
    .replace(/<\/?(?:b|i|code|pre)>/g, "")
    .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
}
