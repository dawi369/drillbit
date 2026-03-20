import { useCallback, useState } from "react";

import type { AssistantFieldStatus } from "@/components/answer/assistant-header";

function extractRevealDraft(rawText: string) {
  const guidanceMatch = rawText.match(/"guidance"\s*:\s*"([\s\S]*?)(?<!\\)"\s*,/);
  const answerMatch = rawText.match(/"answer"\s*:\s*"([\s\S]*?)(?<!\\)"\s*}/);

  const decode = (value?: string) => {
    if (!value) {
      return null;
    }

    try {
      return JSON.parse(`"${value}"`) as string;
    } catch {
      return value
        .replace(/\\n/g, "\n")
        .replace(/\\"/g, '"')
        .replace(/\\\\/g, "\\");
    }
  };

  return {
    guidance: decode(guidanceMatch?.[1]),
    answer: decode(answerMatch?.[1]),
  };
}

export function useAssistantFieldState() {
  const [status, setStatus] = useState<AssistantFieldStatus>("idle");
  const [text, setText] = useState<string | null>(null);
  const [answer, setAnswer] = useState<string | null>(null);

  const reset = useCallback((nextStatus: AssistantFieldStatus = "idle") => {
    setStatus(nextStatus);
    setText(null);
    setAnswer(null);
  }, []);

  const begin = useCallback(() => {
    setStatus("thinking");
    setText(null);
    setAnswer(null);
  }, []);

  const streamText = useCallback((value: string) => {
    setStatus("streaming");
    setText(value);
  }, []);

  const streamRevealDraft = useCallback((rawText: string) => {
    setStatus("streaming");
    const draft = extractRevealDraft(rawText);
    if (draft.guidance) {
      setText(draft.guidance);
    }
    if (draft.answer) {
      setAnswer(draft.answer);
    }
  }, []);

  const finish = useCallback((value: string, nextAnswer?: string | null) => {
    setStatus("done");
    setText(value);
    setAnswer(nextAnswer ?? null);
  }, []);

  const fail = useCallback((message: string) => {
    setStatus("error");
    setText(message);
  }, []);

  return {
    status,
    text,
    answer,
    reset,
    begin,
    streamText,
    streamRevealDraft,
    finish,
    fail,
  };
}
