import Constants from "expo-constants";
import { fetch as expoFetch } from "expo/fetch";
import * as SecureStore from "expo-secure-store";

const OPENROUTER_API_KEY_KEY = "OPENROUTER_API_KEY";
const OPENROUTER_CHAT_URL = "https://openrouter.ai/api/v1/chat/completions";

type OpenRouterMessage = {
  role: "system" | "user" | "assistant";
  content: string;
};

type OpenRouterChoice = {
  message?: {
    content?: string | null;
  };
};

type OpenRouterStreamChoice = {
  delta?: {
    content?: string | null;
  };
};

type OpenRouterResponse = {
  choices?: OpenRouterChoice[];
};

type OpenRouterStreamResponse = {
  choices?: OpenRouterStreamChoice[];
};

function createOpenRouterHeaders(apiKey: string) {
  return {
    Authorization: `Bearer ${apiKey}`,
    "Content-Type": "application/json",
  };
}

function parseOpenRouterStreamEvent(rawEvent: string) {
  const lines = rawEvent.split(/\r?\n/);
  const dataLines = lines
    .filter((line) => line.startsWith("data:"))
    .map((line) => line.slice(5).trim())
    .filter(Boolean);

  return dataLines;
}

export async function getOpenRouterApiKey() {
  const storedKey = await SecureStore.getItemAsync(OPENROUTER_API_KEY_KEY);
  const runtimeKey =
    (Constants.expoConfig?.extra?.openRouterApiKey as string | undefined) ?? null;

  return storedKey ?? runtimeKey;
}

export async function createOpenRouterChatCompletion({
  model,
  messages,
}: {
  model: string;
  messages: OpenRouterMessage[];
}) {
  const apiKey = await getOpenRouterApiKey();
  if (!apiKey) {
    throw new Error("Missing OpenRouter API key.");
  }

  const response = await fetch(OPENROUTER_CHAT_URL, {
    method: "POST",
    headers: createOpenRouterHeaders(apiKey),
    body: JSON.stringify({
      model,
      messages,
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(
      `OpenRouter request failed with ${response.status}: ${errorText || "unknown error"}`,
    );
  }

  const payload = (await response.json()) as OpenRouterResponse;
  const content = payload.choices?.[0]?.message?.content?.trim();

  if (!content) {
    throw new Error("OpenRouter returned an empty response.");
  }

  return content;
}

export async function streamOpenRouterChatCompletion({
  model,
  messages,
  onTextDelta,
}: {
  model: string;
  messages: OpenRouterMessage[];
  onTextDelta?: (textDelta: string) => void;
}) {
  const apiKey = await getOpenRouterApiKey();
  if (!apiKey) {
    throw new Error("Missing OpenRouter API key.");
  }

  const response = await expoFetch(OPENROUTER_CHAT_URL, {
    method: "POST",
    headers: createOpenRouterHeaders(apiKey),
    body: JSON.stringify({
      model,
      messages,
      stream: true,
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(
      `OpenRouter request failed with ${response.status}: ${errorText || "unknown error"}`,
    );
  }

  if (!response.body) {
    throw new Error("OpenRouter streaming response did not include a body.");
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let fullText = "";

  while (true) {
    const { done, value } = await reader.read();

    if (done) {
      buffer += decoder.decode();
    } else {
      buffer += decoder.decode(value, { stream: true });
    }

    let eventBoundary = buffer.indexOf("\n\n");
    while (eventBoundary >= 0) {
      const rawEvent = buffer.slice(0, eventBoundary);
      buffer = buffer.slice(eventBoundary + 2);

      for (const eventData of parseOpenRouterStreamEvent(rawEvent)) {
        if (eventData === "[DONE]") {
          return fullText.trim();
        }

        const payload = JSON.parse(eventData) as OpenRouterStreamResponse;
        const textDelta = payload.choices?.[0]?.delta?.content;

        if (!textDelta) {
          continue;
        }

        fullText += textDelta;
        onTextDelta?.(textDelta);
      }

      eventBoundary = buffer.indexOf("\n\n");
    }

    if (done) {
      break;
    }
  }

  return fullText.trim();
}
