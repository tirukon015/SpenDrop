// Local models through Ollama (https://ollama.com) — RM0 API cost for development. Uses the native /api/chat
// endpoint with tool calling; pick a model that supports tools (e.g. qwen2.5, qwen3, llama3.1, mistral-nemo).
import { ProviderError, parseArguments, type ChatMessage, type ChatProvider, type ChatResponse, type ToolSpec } from "./types";

interface OllamaToolCall { id?: string; function?: { name?: string; arguments?: unknown } }

export class OllamaProvider implements ChatProvider {
  readonly name = "ollama";
  constructor(readonly model: string, private readonly baseUrl: string, private readonly timeoutMs: number) {}

  async chat({ messages, tools, signal }: { messages: ChatMessage[]; tools: ToolSpec[]; signal?: AbortSignal }): Promise<ChatResponse> {
    const body = {
      model: this.model,
      stream: false,
      options: { temperature: 0 },
      keep_alive: "10m",
      tools: tools.map((t) => ({ type: "function", function: t })),
      messages: messages.map((m) => {
        if (m.role === "tool") return { role: "tool", content: m.content, tool_name: m.name };
        if (m.role === "assistant" && m.toolCalls?.length)
          return { role: "assistant", content: m.content, tool_calls: m.toolCalls.map((c) => ({ function: { name: c.name, arguments: c.arguments } })) };
        return { role: m.role, content: m.content };
      }),
    };
    let response: Response;
    try {
      response = await fetch(`${this.baseUrl}/api/chat`, {
        method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body),
        signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(this.timeoutMs)]) : AbortSignal.timeout(this.timeoutMs),
      });
    } catch (error) {
      throw new ProviderError(error instanceof Error && error.name === "TimeoutError" ? "Local AI timed out" : "Local AI service unavailable", error instanceof Error && error.name === "TimeoutError" ? "timeout" : "unavailable");
    }
    if (!response.ok) {
      const detail = await response.text().catch(() => "");
      if (/does not support tools/.test(detail)) throw new ProviderError(`Local model ${this.model} doesn't support tool calling — choose a tools-capable model`, "bad_response");
      throw new ProviderError(`Local AI returned HTTP ${response.status}`, response.status === 404 ? "bad_response" : "unavailable");
    }
    const json = (await response.json().catch(() => null)) as { message?: { content?: string; tool_calls?: OllamaToolCall[] }; prompt_eval_count?: number; eval_count?: number } | null;
    if (!json?.message) throw new ProviderError("Local AI returned an unexpected response", "bad_response");
    return {
      content: typeof json.message.content === "string" ? json.message.content : "",
      toolCalls: (json.message.tool_calls ?? []).map((c, i) => ({ id: c.id ?? `call_${i}`, name: String(c.function?.name ?? ""), arguments: parseArguments(c.function?.arguments) })),
      usage: { inputTokens: json.prompt_eval_count, outputTokens: json.eval_count },
    };
  }

  /** Reachable, the model is installed, and it supports tool calling. */
  async available() {
    try {
      const r = await fetch(`${this.baseUrl}/api/show`, { method: "POST", body: JSON.stringify({ model: this.model }), signal: AbortSignal.timeout(3000) });
      if (!r.ok) return false;
      const info = (await r.json()) as { capabilities?: string[] };
      return !info.capabilities || info.capabilities.includes("tools");
    } catch {
      return false;
    }
  }
}
