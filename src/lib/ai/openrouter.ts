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

type OpenRouterResponse = {
  choices?: OpenRouterChoice[];
};

export async function getOpenRouterApiKey() {
  const storedKey = await SecureStore.getItemAsync(OPENROUTER_API_KEY_KEY);
  return storedKey ?? process.env.EXPO_PUBLIC_OPENROUTER_API_KEY ?? process.env.OPENROUTER_API_KEY ?? null;
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
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
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
