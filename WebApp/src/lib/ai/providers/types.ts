// Provider-independent chat interface. SpenDrop's tools, prompts and security never depend on which model runs:
// swapping Qwen ↔ Llama ↔ Gemma, or Ollama ↔ a hosted API, only changes configuration.

export interface ToolCall {
  id: string;
  name: string;
  /** Raw arguments from the model — untrusted until validated by the tool registry. */
  arguments: unknown;
}

export type ChatMessage =
  | { role: "system" | "user"; content: string }
  | { role: "assistant"; content: string; toolCalls?: ToolCall[] }
  | { role: "tool"; content: string; toolCallId: string; name: string };

export interface ToolSpec { name: string; description: string; parameters: Record<string, unknown> }

export interface ChatResponse {
  content: string;
  toolCalls: ToolCall[];
  usage?: { inputTokens?: number; outputTokens?: number };
}

export interface ChatProvider {
  /** "ollama", "openai-compatible", … (shown in diagnostics; never a secret). */
  readonly name: string;
  readonly model: string;
  chat(request: { messages: ChatMessage[]; tools: ToolSpec[]; signal?: AbortSignal }): Promise<ChatResponse>;
  /** Cheap reachability check for the status endpoint. */
  available(): Promise<boolean>;
}

/** A provider failure. The message is safe to log; it never contains keys or request bodies. */
export class ProviderError extends Error {
  constructor(message: string, readonly kind: "unavailable" | "timeout" | "bad_response" | "auth" = "unavailable") {
    super(message);
  }
}

export function parseArguments(raw: unknown): unknown {
  if (typeof raw !== "string") return raw ?? {};
  try {
    return JSON.parse(raw);
  } catch {
    return { __invalid_json: true };
  }
}
