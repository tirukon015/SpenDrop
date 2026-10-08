// Local model benchmark (not part of CI). Gives each model ONLY the SpenDrop tool definitions and the system
// prompt, asks every question in the NLU evaluation set, and scores the first decision:
//   • questions with an expected tool → the right tool with the key arguments (category / merchant / period / operation)
//   • unsupported, unsafe or ambiguous questions → no tool call at all
// Also records latency per question and the model's memory use (Ollama /api/ps). Run:
//   OLLAMA_BENCH=1 AI_MODELS=qwen2.5:3b,qwen2.5:7b npx vitest run tests/ai/model-benchmark.test.ts
import { describe, expect, it } from "vitest";
import { modelUserMessage } from "@/lib/ai/model";
import { systemPrompt } from "@/lib/ai/prompts/system";
import { OllamaProvider } from "@/lib/ai/providers/ollama";
import { toolSpecs } from "@/lib/ai/registry";
import { NLU_CASES } from "./nlu-dataset";

const BASE = process.env.OLLAMA_BASE_URL ?? "http://127.0.0.1:11434";
const models = (process.env.AI_MODELS ?? "qwen2.5:3b").split(",").map((m) => m.trim()).filter(Boolean);
const KEY_ARGS = ["category", "merchant", "operation", "groupBy", "paymentChannel", "fundingAccount"];

describe.skipIf(!process.env.OLLAMA_BENCH)("local model benchmark", () => {
  for (const model of models) {
    it(model, async () => {
      const provider = new OllamaProvider(model, BASE, 120_000);
      const system = systemPrompt({ today: "2026-10-07", weekday: "Wednesday", timeZone: "Asia/Kuala_Lumpur" });
      const cases = NLU_CASES.filter((c) => !c.after && !c.expect.memory && c.expect.intent !== "UNKNOWN" && c.expect.intent !== "GENERAL");
      let toolOk = 0, argsOk = 0, refuseOk = 0, toolN = 0, refuseN = 0;
      const ms: number[] = [];
      const misses: string[] = [];
      for (const c of cases) {
        const started = Date.now();
        // NORMALIZE=1: the production model route, which adds SpenDrop's normalised English reading as a hint.
        const content = process.env.NORMALIZE ? modelUserMessage(c.q, ["Starbucks", "Grab", "Shopee", "Maybank", "CIMB"]) : c.q;
        const r = await provider.chat({ messages: [{ role: "system", content: system }, { role: "user", content }], tools: toolSpecs() });
        ms.push(Date.now() - started);
        const call = r.toolCalls[0];
        if (c.expect.tool) {
          toolN++;
          if (call?.name === c.expect.tool) {
            toolOk++;
            const args = (call.arguments ?? {}) as Record<string, unknown>;
            const want = Object.entries(c.expect.args ?? {}).filter(([k]) => KEY_ARGS.includes(k));
            if (want.every(([k, v]) => String(args[k] ?? "").toLowerCase() === String(v).toLowerCase())) argsOk++;
            else misses.push(`args  ${c.q} → ${JSON.stringify(args)}`);
          } else misses.push(`tool  ${c.q} → ${call?.name ?? "(no tool)"}`);
        } else {
          refuseN++;
          if (!call) refuseOk++; else misses.push(`safety ${c.q} → called ${call.name}`);
        }
      }
      const ps = await fetch(`${BASE}/api/ps`).then((x) => x.json()).catch(() => ({ models: [] })) as { models: { name: string; size: number; size_vram: number }[] };
      const mem = ps.models.find((m) => m.name.startsWith(model));
      const sorted = [...ms].sort((a, b) => a - b);
      console.log([
        `MODEL ${model}${process.env.NORMALIZE ? " (with normalised hint)" : " (raw question)"}`,
        `  right tool        ${toolOk}/${toolN} (${Math.round((toolOk / toolN) * 100)}%)`,
        `  right key args    ${argsOk}/${toolN} (${Math.round((argsOk / toolN) * 100)}%)`,
        `  no tool when unsafe/off-topic/ambiguous  ${refuseOk}/${refuseN}`,
        `  latency median ${sorted[Math.floor(sorted.length / 2)]} ms, p90 ${sorted[Math.floor(sorted.length * 0.9)]} ms`,
        `  memory ${mem ? `${(mem.size / 1e9).toFixed(1)} GB (${(mem.size_vram / 1e9).toFixed(1)} GB on GPU)` : "n/a"}`,
        ...misses.slice(0, 25).map((m) => `  ✗ ${m}`),
      ].join("\n"));
      expect(toolN).toBeGreaterThan(0);
    }, 1_800_000);
  }
});
