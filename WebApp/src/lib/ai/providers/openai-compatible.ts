// Any OpenAI-compatible Chat Completions endpoint: a hosted API, or a self-hosted server (vLLM, LM Studio,
// llama.cpp server, …). The API key stays on the server (AI_API_KEY) and is only sent to AI_BASE_URL.
import { ProviderError, parseArguments, type ChatMessage, type ChatProvider, type ChatResponse, type ToolSpec } from "./types";

interface OpenAIToolCall { id: string; function: { name: string; arguments: string } }

export class OpenAICompatibleProvider implements ChatProvider {
  readonly name = "openai-compatible";
  constructor(readonly model: string, private readonly baseUrl: string, private readonly apiKey: string | undefined, private readonly timeoutMs: number) {}

  private headers() {
    return { "content-type": "application/json", ...(this.apiKey ? { authorization: `Bearer ${this.apiKey}` } : {}) };
  }

  async chat({ messages, tools, signal }: { messages: ChatMessage[]; tools: ToolSpec[]; signal?: AbortSignal }): Promise<ChatResponse> {
    const body = {
      model: this.model,
      temperature: 0,
      tools: tools.map((t) => ({ type: "function", function: t })),
      messages: messages.map((m) => {
        if (m.role === "tool") return { role: "tool", tool_call_id: m.toolCallId, content: m.content };
        if (m.role === "assistant" && m.toolCalls?.length)
          return { role: "assistant", content: m.content || null, tool_calls: m.toolCalls.map((c) => ({ id: c.id, type: "function", function: { name: c.name, arguments: JSON.stringify(c.arguments ?? {}) } })) };
        return { role: m.role, content: m.content };
      }),
    };
    let response: Response;
    try {
      response = await fetch(`${this.baseUrl}/chat/completions`, {
        method: "POST", headers: this.headers(), body: JSON.stringify(body),
        signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(this.timeoutMs)]) : AbortSignal.timeout(this.timeoutMs),
      });
    } catch (error) {
      const timeout = error instanceof Error && error.name === "TimeoutError";
      throw new ProviderError(timeout ? "AI provider timed out" : "AI provider unavailable", timeout ? "timeout" : "unavailable");
    }
    if (response.status === 401 || response.status === 403) throw new ProviderError("AI provider rejected the credentials", "auth");
    if (!response.ok) throw new ProviderError(`AI provider returned HTTP ${response.status}`);
    const json = (await response.json().catch(() => null)) as {
      choices?: { message?: { content?: string | null; tool_calls?: OpenAIToolCall[] } }[]; usage?: { prompt_tokens?: number; completion_tokens?: number };
    } | null;
    const message = json?.choices?.[0]?.message;
    if (!message) throw new ProviderError("AI provider returned an unexpected response", "bad_response");
    return {
      content: message.content ?? "",
      toolCalls: (message.tool_calls ?? []).map((c) => ({ id: c.id, name: c.function.name, arguments: parseArguments(c.function.arguments) })),
      usage: { inputTokens: json?.usage?.prompt_tokens, outputTokens: json?.usage?.completion_tokens },
    };
  }

  async available() {
    try {
      const r = await fetch(`${this.baseUrl}/models`, { headers: this.headers(), signal: AbortSignal.timeout(3000) });
      return r.ok;
    } catch {
      return false;
    }
  }
}
