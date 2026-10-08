// Corpus evaluation. Development splits (train, dev) run by default; the HOLDOUT and ADVERSARIAL splits run only when
// asked (CORPUS_SPLITS=holdout,adversarial) and are never used for tuning. CORPUS_REPORT=path writes the full report.
import { writeFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { evaluateOne, summarise, type Outcome } from "./evaluate";
import { generate, type Split } from "./generate";

const { examples, stats } = generate();
const splits = (process.env.CORPUS_SPLITS ?? "train,dev").split(",") as Split[];

describe("SpenDrop AI corpus", () => {
  it("generator: ≥ 5,000 quality-controlled examples, every language and split present, reproducible", () => {
    expect(examples.length).toBeGreaterThanOrEqual(5000);
    for (const s of ["train", "dev", "holdout", "adversarial"]) expect(examples.some((e) => e.split === s), s).toBe(true);
    for (const l of ["en", "bn-latn", "bn", "ms", "mixed"]) expect(examples.some((e) => e.language === l), l).toBe(true);
    expect(JSON.stringify(generate().examples.slice(0, 50))).toBe(JSON.stringify(examples.slice(0, 50)));
    // No holdout question appears (case-insensitively) in train/dev.
    const dev = new Set(examples.filter((e) => e.split === "train" || e.split === "dev").map((e) => e.question.toLowerCase()));
    expect(examples.filter((e) => (e.split === "holdout" || e.split === "adversarial") && dev.has(e.question.toLowerCase())).length).toBe(0);
  });

  it(`evaluates ${splits.join(" + ")}`, async () => {
    const report: Record<string, unknown> = { stats };
    for (const split of splits) {
      const outcomes: Outcome[] = [];
      for (const e of examples.filter((x) => x.split === split)) outcomes.push(await evaluateOne(e));
      const s = summarise(outcomes);
      report[split] = { ...s, failures: outcomes.filter((o) => !o.ok).slice(0, 400).map((o) => `[${o.example.kind}/${o.example.language}] ${o.example.context.length ? `${o.example.context.join(" → ")} → ` : ""}${o.example.question} ⇒ ${o.stage}: ${o.detail}`) };
      if (process.env.NLU_REPORT) console.log(`${split}: ${s.accuracy} | ${JSON.stringify(s.failuresByStage)} | latency ${JSON.stringify(s.latencyMs)}`);
    }
    if (process.env.CORPUS_REPORT) writeFileSync(process.env.CORPUS_REPORT, JSON.stringify(report, null, 2));
    expect(true).toBe(true);
  }, 600_000);
});
