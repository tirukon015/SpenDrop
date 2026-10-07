// Server-side provider configuration from environment variables (never NEXT_PUBLIC_*: nothing here reaches the
// browser). AI_PROVIDER=none (default) answers with SpenDrop's deterministic tools only — no model, no cost.
//
//   AI_PROVIDER=ollama             AI_MODEL=qwen2.5:7b   OLLAMA_BASE_URL=http://127.0.0.1:11434
//   AI_PROVIDER=openai-compatible  AI_MODEL=…            AI_BASE_URL=https://…/v1   AI_API_KEY=…
//   AI_TIMEOUT_MS=60000            AI_DEBUG=1 (diagnostics in the UI; development only)
import { OllamaProvider } from "./ollama";
import { OpenAICompatibleProvider } from "./openai-compatible";
import type { ChatProvider } from "./types";

export type ProviderSetting = "none" | "ollama" | "openai-compatible";

export interface AiServerConfig {
  provider: ProviderSetting;
  model: string | null;
  debug: boolean;
}

function env(name: string): string | undefined {
  const v = process.env[name];
  return v && v.trim() ? v.trim() : undefined;
}

export function serverConfig(): AiServerConfig {
  const raw = (env("AI_PROVIDER") ?? "none").toLowerCase();
  const provider: ProviderSetting = raw === "ollama" || raw === "openai-compatible" ? raw : "none";
  return { provider, model: provider === "none" ? null : env("AI_MODEL") ?? null, debug: env("AI_DEBUG") === "1" && process.env.NODE_ENV !== "production" };
}

/** The configured model provider, or null when SpenDrop AI runs without a model. */
export function getProvider(): ChatProvider | null {
  const { provider, model } = serverConfig();
  const timeout = Number(env("AI_TIMEOUT_MS") ?? 60_000);
  if (provider === "none" || !model) return null;
  if (provider === "ollama") return new OllamaProvider(model, (env("OLLAMA_BASE_URL") ?? "http://127.0.0.1:11434").replace(/\/$/, ""), timeout);
  const base = env("AI_BASE_URL");
  if (!base) return null;
  return new OpenAICompatibleProvider(model, base.replace(/\/$/, ""), env("AI_API_KEY"), timeout);
}

export type { ChatProvider } from "./types";
