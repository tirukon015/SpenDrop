// Optional live check against a local Ollama model (not part of CI): OLLAMA_SMOKE=1 AI_MODEL=qwen2.5:7b npx vitest run tests/ai/ollama.smoke.test.ts
// Questions the deterministic planner doesn't handle go to the model, which must use the tools and stay grounded.
import { describe, expect, it } from "vitest";
import { answerWithModel } from "@/lib/ai/model";
import { OllamaProvider } from "@/lib/ai/providers/ollama";
import { ctx, historyStore, USER_A } from "./fixtures";

const model = process.env.AI_MODEL ?? "qwen2.5:7b";
describe.skipIf(!process.env.OLLAMA_SMOKE)(`live Ollama (${model})`, () => {
  const provider = new OllamaProvider(model, process.env.OLLAMA_BASE_URL ?? "http://127.0.0.1:11434", 120_000);
  it.each([
    "On which weekday do I usually spend the most on coffee?",
    "Did my transport costs go anywhere unexpected recently?",
    "What is budgeting?",
  ])("%s", async (q) => {
    const a = await answerWithModel({ message: q, ctx: ctx(), repo: historyStore().forUser(USER_A), provider, history: [], focus: null });
    console.log(`\nQ: ${q}\nroute=${a.meta.route} tools=${a.meta.tools.map((t) => `${t.name}:${t.ok}`).join(",")} evidence=${JSON.stringify(a.evidence.map((e) => e.filters))} fallback=${a.meta.groundingFallback ?? false} ms=${a.meta.totalMs} tokens=${JSON.stringify(a.meta.tokens)}\nA: ${a.text}`);
    expect(a.status).not.toBe("error");
  }, 300_000);
});
