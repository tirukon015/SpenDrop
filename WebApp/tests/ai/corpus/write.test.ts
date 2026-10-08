// WRITE_CORPUS=1 npx vitest run tests/ai/corpus/write.test.ts → writes the dataset (JSONL per split) + statistics.
import { writeFileSync } from "node:fs";
import path from "node:path";
import { it } from "vitest";
import { FIXTURES, generate } from "./generate";

it.skipIf(!process.env.WRITE_CORPUS)("writes the corpus", () => {
  const { examples, stats } = generate();
  const dir = path.join(__dirname, "data");
  for (const split of ["train", "dev", "holdout", "adversarial"]) {
    const rows = examples.filter((e) => e.split === split).map((e) => ({
      id: e.id, language: e.language, difficulty: e.difficulty, intent: e.kind, fixture: e.fixture, template: e.template,
      context: e.context, question: e.question, expected_intents: e.expect.intents ?? null, expected_status: e.expect.status ?? "answered",
      expected_filters: { category: e.expect.category, merchants: e.expect.merchants, remark_topic: e.expect.keyword ?? false, period: e.expect.span },
      required_tools: e.expect.intents?.includes("CALCULATE") ? ["calculate_spending"] : e.expect.intents?.includes("SEARCH") ? ["search_transactions"] : [],
      expected_result: e.expect.result ?? null, operation: e.expect.operation ?? null, ambiguity: e.ambiguity, security: e.security,
    }));
    writeFileSync(path.join(dir, `${split}.jsonl`), rows.map((r) => JSON.stringify(r)).join("\n") + "\n");
  }
  writeFileSync(path.join(dir, "fixtures.json"), JSON.stringify(FIXTURES, null, 1));
  writeFileSync(path.join(dir, "stats.json"), JSON.stringify(stats, null, 2));
});
