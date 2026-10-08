# SpenDrop AI — "Ask SpenDrop"

Ask anything about your own money, and get an answer that SpenDrop has actually checked against your records.

> **Principle:** QUESTION → UNDERSTAND → TOOL → DATABASE → VERIFY → EXPLAIN. Never QUESTION → GUESS → ANSWER.
> The model is never the security authority. Authentication, validated read-only tools and Postgres RLS are.

Status: **Web MVP (read-only)**. Android/iOS can call the same `/api/ai/chat` endpoint later.

---

## 1. How a question flows

```
Browser (/ask)                        Server (Next.js route handler)                         Supabase Postgres
──────────────                        ──────────────────────────────                         ─────────────────
POST /api/ai/chat  ─────────────────▶ 1. same-origin + JSON + size + strict schema
{ message, conversationId?,           2. authenticate(): user id = verified JWT `sub`
  timeZone? }                            (a userId/user_id in the body → 400)
                                      3. rate limit (user's own questions in ai_messages)
                                      4. conversation must be the user's (else 404)
                                      5. AiContext { userId, timeZone, today, requestId }  (frozen)
                                      6. Planner (deterministic) ── understood? ──┐
                                            │ no                                  │ yes
                                            ▼                                     ▼
                                      7. Model (if configured)              executeTool(name, args, ctx, repo)
                                         picks tools ──────────────────────▶   • strict zod validation
                                                                                • permission (read-only)
                                                                                • timeout, row/period limits
                                                                                • SupabaseRepository:  ─────▶ user's JWT → RLS
                                                                                  explicit user_id filter      + user_id = ctx.userId
                                                                                  + per-row owner check
                                      8. Composer: deterministic answer + evidence blocks
                                         Model text must pass grounding (amounts, %, counts,
                                         names all present in tool results) or it is replaced
                                      9. Store Q + A in ai_messages (RLS), log ids/timings only
◀──────────────────────────────────── { conversationId, answer }
```

**Hybrid routing.** Most questions ("How much did I spend on food this week?", "Where did my RM15 go on 7 October?", "Why?", "Which restaurants?") are understood by the deterministic planner and answered without any model — exact, instant and free. Only what the planner can't understand goes to the configured model, which can call the *same* tools. With no model configured, SpenDrop explains what it can answer instead of guessing.

## 2. Where things live (`WebApp/src/lib/ai/`)

| File | Role |
|---|---|
| `types.ts` | `AiContext` (who is asking — server-made only), answers, evidence, focus |
| `schemas.ts` | zod schemas for tool inputs and the chat request (strict: unknown keys rejected) |
| `time.ts` | Dates in the user's IANA time zone; Monday–Sunday weeks; fair "previous period" |
| `repository.ts` | `FinanceRepository` interface; in-memory versions for the demo and tests |
| `supabase-repository.ts` | The server repository: user JWT (RLS) + explicit `user_id` filter + per-row owner check |
| `tools.ts` | The six tools (all money maths, integer sen, same spending rule as the app) |
| `registry.ts` | Tool registry: name, description, permission, schema, timeout, handler; `executeTool()` |
| `planner.ts` | Deterministic intent + entities (amount, period, merchant, category, account, channel, currency) |
| `compose.ts` | Deterministic answer text + evidence blocks from tool results |
| `core.ts` | Planner → tools → composer pipeline (also runs in the browser demo) |
| `model.ts` | Model loop (tool calls capped), compact tool results, grounding fallback |
| `grounding.ts` | Checks every figure and name in a model answer against tool results |
| `prompts/system.ts` | Versioned system prompt |
| `providers/` | `ChatProvider` interface; Ollama and OpenAI-compatible providers; env config |
| `engine.ts` | Server orchestration + structured request log |
| `conversations.ts` | Conversation store (Supabase, RLS) and focus re-validation |
| `chat-handler.ts` | The `/api/ai/chat` logic (injectable, tested) |
| `server.ts` | `authenticate()`, same-origin check, JSON errors |

Routes: `POST /api/ai/chat`, `GET /api/ai/conversations`, `GET|DELETE /api/ai/conversations/:id`, `GET /api/ai/status`. UI: `src/app/(app)/ask`, `src/components/ask/`.

## 3. Tools (read-only)

| Tool | Permission | What it returns |
|---|---|---|
| `search_transactions` | READ_FINANCIAL_DATA | Matching transactions (default 20, max 100), total count, ranking by closeness to a remembered amount/day, confidence |
| `calculate_spending` | READ_ANALYTICS | sum / count / average / min / max, optional group by category, merchant, funding account, payment channel or day; **per currency**; refunds listed separately |
| `compare_periods` | READ_ANALYTICS | Two periods: totals, difference, %, counts, biggest changes, largest transactions |
| `get_transaction` | READ_RECEIPTS | One transaction (ownership enforced): fields, split, note, whether a receipt exists |
| `get_weekly_summary` | READ_ANALYTICS | Week total, vs same days last week, vs 4-week average, categories, by day, top merchants/accounts/channels |
| `find_unusual_spending` | READ_ANALYTICS | Against the user's OWN previous 8 weeks: total/category spikes, unusually large transactions, new merchants; "not enough history" when < 3 weeks |

No write permission exists in the MVP (`ENABLED_PERMISSIONS`). Unknown tools, `user_id`/`userId` arguments, SQL, impossible dates, out-of-range limits or periods over 3 years are rejected by validation.

### Financial rules the tools follow
- **Spending** = full amount if I paid, my share if someone else paid (`lib/domain/ledger.ts` `spendingMinor`) — the same figure as Home and Breakdown.
- **Money** in integer minor units; averages rounded once at the end. Never floating-point sums.
- **Currencies never mixed**: results are per currency; no exchange rates are invented. "RM" and "MYR" are the same.
- **Refunds** are reported next to spending, never silently netted. **Own transfers** and other money movements are not spending.
- **Funding account ≠ payment channel.** "From Maybank" filters `funding_account`; "using Apple Pay" filters `payment_channel`; "QR" covers QR Payment, DuitNow QR and Touch 'n Go QR.
- **Dates** are resolved in the user's time zone (sent by the browser, validated; default Asia/Kuala_Lumpur). An in-progress month/week is compared with the same days of the previous one ("1–7 Oct vs 1–7 Sep").
- **Lookups** ("RM15") match ±10% (min RM1), "around RM15" ±20% (min RM2); configurable in `config.ts`. If nothing matches, the search widens one step at a time (±1 day, last 90 days, wider amount) and the answer says so.
- SpenDrop doesn't store locations or receipt text (OCR runs on the device), so the AI says so instead of pretending.

## 4. Security model (defence in depth)

1. **Authentication** — `supabase.auth.getClaims()` verifies the session JWT; the user id is its `sub`. Signed out → 401. The proxy doesn't redirect `/api/*`, so the API answers JSON.
2. **No client-chosen identity** — the chat body schema is strict; `userId`/`user_id` → 400 before anything runs. Tool schemas are strict too, so a model can't pass a user id either.
3. **Execution context** — `AiContext` is built and frozen on the server; tools get it as a separate argument.
4. **User-scoped repository** — the server never uses a service-role key. Queries run with the user's own JWT (RLS), add `user_id = ctx.userId`, and refuse any returned row owned by someone else.
5. **RLS** — every financial and AI table is owner-only; `ai_messages` → `ai_conversations` uses a composite `(id, user_id)` foreign key, so a message can't be attached to another user's conversation even with a forged id.
6. **Ownership of ids** — another user's transaction or conversation id is "not found", never revealed.
7. **Model treated as untrusted** — tool calls capped (`maxToolCalls`), timeouts, validation, and grounding: any amount, %, count, merchant/account or category name not present in a tool result → the model's text is replaced by SpenDrop's deterministic answer. Claims of having checked data without a tool call are rejected.
8. **Prompt injection** — merchant names, notes and receipt-related text are only ever passed as JSON data inside tool messages. Read-only tools mean there is nothing harmful to trigger.
9. **Output** — answers are plain text rendered by React (escaped); markdown/HTML is stripped from model text.
10. **CSRF / abuse** — same-origin check on POST/DELETE, JSON only, 4 KB body, 500-character questions, 15 questions/minute and 150/hour per user.
11. **Privacy minimisation** — the model sees aggregates for "how much" questions and only the matching rows for "which" questions; ids, notes and receipts only when a specific transaction is asked about. Nothing is used to train any model. Conversations are deletable; deleting the account deletes them (cascade).
12. **Logging** — one JSON line per question: request id, user id, conversation id, intent, route, provider/model, tool names + timings, status, token counts. No amounts, merchants, question text or tokens/keys.

## 5. Database

Migrations `20261009000000_spendrop_ai.sql` (conversations) and `20261010000000_spendrop_ai_memory.sql` (personal rules), both additive. The first: `ai_conversations`, `ai_messages` with owner-only RLS, append-only messages, size limits and indexes. No new indexes on financial tables — the existing `(user_id, date desc)` index serves the AI's date-ranged reads; add more only after measuring (`EXPLAIN ANALYZE`).

**Apply it** (Supabase Dashboard → SQL Editor, or `supabase db push`) before using Ask SpenDrop in production. Until then the chat endpoint returns a clear "not set up" message (503).

## 6. Configuration

Server-only environment variables (never `NEXT_PUBLIC_*`):

| Variable | Default | Meaning |
|---|---|---|
| `AI_PROVIDER` | `none` | `none` (deterministic only, RM0), `ollama`, or `openai-compatible` |
| `AI_MODEL` | — | Model name, e.g. `qwen2.5:7b` |
| `OLLAMA_BASE_URL` | `http://127.0.0.1:11434` | Ollama server |
| `AI_BASE_URL` | — | OpenAI-compatible base URL (hosted or self-hosted: vLLM, LM Studio, llama.cpp) ending in `/v1` |
| `AI_API_KEY` | — | Key for `AI_BASE_URL` (kept on the server) |
| `AI_TIMEOUT_MS` | `60000` | Per model call |
| `AI_DEBUG` | — | `1` shows request diagnostics under each answer (ignored in production) |

Changing model or provider never requires touching tools: they belong to SpenDrop; the model only decides which to call.

### Local development with Ollama (RM0)

```bash
# 1. Install Ollama (https://ollama.com) and pull a model that supports TOOL CALLING
ollama pull qwen2.5:7b         # recommended on a 16 GB Apple-silicon Mac; qwen2.5:3b also works but answers worse
# (vision-only models such as qwen2.5vl don't support tools and will be reported as unavailable)

# 2. WebApp/.env.local
AI_PROVIDER=ollama
AI_MODEL=qwen2.5:7b

# 3. Run and ask
cd WebApp && npm run dev        # http://localhost:3000/ask — "How much did I spend this week?"
```

Demo mode (`NEXT_PUBLIC_SPENDROP_DEMO=1`) runs the deterministic engine in the browser over the synthetic data; nothing is sent anywhere.

### Production (Vercel)

Vercel can't reach a model on your Mac. Options: leave `AI_PROVIDER=none` (deterministic answers only — the six acceptance questions all work this way), or point `AI_PROVIDER=openai-compatible` at a hosted or self-hosted endpoint. Measure cost and latency per user before choosing.

## 7. Testing

```bash
cd WebApp
npx vitest run tests/ai tests/db      # acceptance, security, dates/time zones, RLS on a real Postgres (PGlite)
npx playwright test -g "Ask SpenDrop" # UI on phone, tablet, laptop, desktop (demo mode)
OLLAMA_SMOKE=1 AI_MODEL=qwen2.5:7b npx vitest run tests/ai/ollama.smoke.test.ts   # optional live model check
```

What the tests prove:
- **Acceptance** (`tests/ai/acceptance.test.ts`): the six MVP questions as one conversation (RM15 on 7 Oct → candidates; food this week → exact total; more this month → fair comparison; Why? → drivers; Which restaurants? → Food merchants; unusual → spikes/large/new), RM10+20+30 = RM60, RM100 vs RM150 = +RM50 / 50%, RM100 + USD100 never 200, RM9999 → no match, ambiguity → asks which, first-time user, insufficient history, account vs channel.
- **Security** (`tests/ai/security.test.ts`): through the real handler — User A's "Where did my RM15 go?" shows only Starbucks, User B's only McDonald's; `user_id` in body → 400; signed-out → 401; other user's conversation → 404; cross-site → 403; rate limit → 429; jailbreak prompts refused; tool validation (user ids, SQL, enums, dates, limits); other user's transaction id → not found; hostile model (forged user id, invented totals, claims without tools, endless calls, outage); prompt injection in merchant/notes.
- **Database** (`tests/db/ai-tables.test.ts`): RLS on the AI tables as real roles, forged conversation/user ids, append-only messages, anon denied, cascade deletes, and cross-user isolation of the expense reads.
- **Dates** (`tests/ai/time.test.ts`): today/yesterday/last Saturday/this & last week/month, explicit dates, Malaysian D/M, time-zone day boundaries, daylight-saving days, fair comparisons.

## 8. Understanding, personalisation and insights (upgrade 2026-10-08)

```
question ─▶ normalise (normalize.ts) ─▶ gates ─▶ planner ─▶ tools (+ personal rules) ─▶ composer ─▶ answer · insight · suggestion
            Malay / Banglish / Bengali     secrets → refuse        intent + entities          ▲
            slang, typos → English         off-topic → limitation  follow-up replay           └ ai_memories (user's own rules)
                                           ambiguous → 1 question
```

**Normalisation** (`normalize.ts`, deterministic, RM0): phrase and word tables for Malay, Banglish and a few Bengali-script words, English slang ("burn", "money gone", "eating out"), abbreviations (wk, mth), and typo correction that only targets SpenDrop's own vocabulary plus the user's merchant/account names (never ordinary English words, short words or words with digits). The answer shows "I read this as …" whenever something was translated or corrected.

**Gates before any tool or model:** passwords/PINs/OTPs → refusal; bank balance → limitation (SpenDrop isn't connected to banks); weather, sports, news, prices, jokes → "I can help with your SpenDrop finances, but I don't have …"; "waste / unnecessary" → one clarifying question; "spend there" without a place in the conversation → "Which merchant or place do you mean?". Off-topic questions are never sent to a model.

**Follow-ups:** "What about last month?", "and Grab?", "gotho week e?" repeat the previous question with only what was named changed (the focus stores the operation / grouping). Bare phrases ("food last week?", "shopee last month") are understood without a verb.

**Personal memory** (migration `20261010000000_spendrop_ai_memory.sql`, table `ai_memories`): only explicit statements are stored — "Grab is transport for me", "No, Grab is Transport", "treat Shopee as shopping", "grab amar jonno transport". "What do you remember about me?" lists them; "forget Grab" deletes. Rules change how answers *group* spending (effective category), never the stored transactions, and every answer that used a rule says so. Owner-only RLS; one user's rule can't affect another; the model has no tool that writes memory. "Transfers between my own accounts aren't expenses" is answered as already true (no rule needed).

**Personal insights** (`get_spending_insights`, `insights.ts`): this month (or week) so far vs the user's OWN normal = the average of the same days in up to 3 earlier months (4 weeks), counting only periods since they started recording (≥ 2 needed). Reports total change, category and merchant changes, larger-than-usual purchases, small payments that add up and weekend vs weekday — each only above thresholds in `config.ts` (≥ 25% and ≥ RM30/month or RM20/week). A suggestion ("If you're trying to reduce spending, Shopping is the category I'd review first") appears only when there is a meaningful increase and a clear main driver. A total for "this week/this month" gets one extra insight line when it differs meaningfully from normal.

**Proactive "I noticed"** (`GET /api/ai/insights`, `proactive.ts`): at most two cards on the Ask screen, only when the same thresholds are passed; none is a normal outcome.

**Answer layout:** status chip for uncertainty / no data / refusal, "I read this as", the direct answer (first sentence, bold), the one block that *is* the answer, then separate Insight and Suggestion cards (the latter labelled "not financial advice"), other details collapsed ("View N transactions"), evidence line and "Why this answer?".

### Evaluation

| Set | What | Result |
|---|---|---|
| `tests/ai/nlu-dataset.ts` (100 cases) | EN, informal, typos, Banglish, Bengali script, Malay, mixed, short, follow-ups, ambiguity, memory, unsupported, injection | 100% (regression set — written with the rules) |
| `tests/ai/nlu-heldout.test.ts` (30) | paraphrases written after the rules | **25/30 (83%) on first run**; the 5 misses were fixed → 30/30, so the set is now partly tuned |
| `tests/ai/model-benchmark.test.ts` | `qwen2.5:3b` alone (tools only, first decision, 63 tool cases + 18 must-not-call cases) | right tool 37%, right key args 32%, no tool on unsafe/off-topic/ambiguous 15/18, median 0.72 s, 2.2 GB |
| same, `NORMALIZE=1` | plus SpenDrop's English reading as a hint | 40% / 30% / 14 of 18 — no meaningful gain, so not used in production |

Conclusion: the deterministic understanding layer is the production path; a small local model is a fallback for questions it doesn't recognise, guarded by validation and grounding. `qwen2.5vl:7b` (installed) can't call tools. Before fine-tuning, benchmark a 7–8B tool-calling model (e.g. `qwen2.5:7b`, `qwen3:8b`, `llama3.1:8b`) with `OLLAMA_BENCH=1 AI_MODELS=… npx vitest run tests/ai/model-benchmark.test.ts`; collect anonymised, consented misunderstandings for a LoRA set only after that.

## 9. Quality pass (2026-10-08): conversation, calculations, evidence

**Conversation layer** (`conversation.ts`) — social vs financial is decided by meaning, not phrase lists:
1. Safety gates first (other users, SQL/injection, secrets, balance, off-topic).
2. *Financial?* Strong signals (money words, amounts, categories, merchants, accounts, channels) always; weak ones
   (periods, intent words) unless the message is addressed to SpenDrop socially; follow-ups when there is context.
3. *Social?* Classified by structure — thanks / goodbye / greeting word families; anything addressed to SpenDrop
   ("you", "tumi", "awak", "তুমি") by what it asks (well-being, activity, identity, abilities, compliment); short chit-chat.
   Replies mirror the user's language (English, Banglish, Bengali, Malay) with natural variation and no tools.
4. Mixed messages ("kemon aso bro, food e koto khoroch hoise?") → short greeting (`preface`) + the verified financial answer.

**Context** — a follow-up is recognised by meaning (explicit marker, a bare period/subject, something relative to the
last answer like "the day before" or "is that normal?"); a message with its own intent is a new question and
inherits nothing. Drill-downs remember the main question (`focus.base`); lookups keep the remembered amount;
offers ("search all my transactions?") are accepted only by an immediate yes.

**Calculation layer** (`calc.ts`) — the only place money formulas exist: exact integer-sen totals (corrupt amounts
throw), averages and shares rounded once (half away from zero), percentage change ((C − P) / P × 100, null when P = 0),
max/min, median, per-day and scaling. Major→minor conversion is float-safe.

**Invariants** (`invariants.ts`) — every tool result is checked before it can be shown: total = Σ listed transactions
= Σ groups = Σ days; count = rows; largest = max; difference = current − previous; percentage = formula. A violation
withholds the answer. Totals and weekly summaries carry the transactions behind them as evidence ("View N
transactions" opens exactly N that add up); "Based on N" always describes the answer's own dataset.

**Dates** — spans are inclusive local days converted to `[start, end)` instants in the user's zone (Malaysia: UTC+8),
weeks Monday–Sunday. Tests cover midnight, 23:59:59.999, month/year boundaries, week edges and the UTC→MYT day shift.

**Understanding fixes** — typo correction only for words of 5+ letters (it had turned "who"→"why", "junk"→"june",
"jay"→"Jaya"); short typos via an explicit table; Banglish/Malay verb stems; whole-word merchant matching with
disclosure when a name matches several merchants; an unrecognised name in a money question is searched as a merchant
(answering "no spending at X" instead of silently answering a different question).

**Evaluation (honest)**

| Set | Result |
|---|---|
| Regression set (`nlu-dataset.ts`, written with the rules) | 101/101 |
| Hold-out v1 (30) | 30/30 (partly tuned earlier) |
| Hold-out v2 (37, frozen before this pass) | 13/37 before → 37/37 after (failures were seen while implementing — partly tuned) |
| **Hold-out v3 (40, written after, never tuned)** | **34/40 (85%)** — all casual and all safety cases right; misses: idioms ("eating up my money", "getting out of hand", "throw away"), "how often", "do I pay more by card or qr", Banglish "barche" |
| Property tests (3 random datasets × filters × periods vs an independent oracle) | all pass |

## 10. Intelligence upgrade (2026-10-08): merchants, remarks, corpus, speed

**Merchant / entity resolution** (`lib/ai/merchant-resolver.ts`): deterministic scoring over the signed-in user's own
merchant names — exact (case/spacing/punctuation/accents ignored) > whole word > prefix (4+ letters) > inner part (5+)
> one typo (5+). Spellings of one merchant (`BIJOYSHARIARALAMIN` / `BIJOY SHARIAR AL AMIN`) are one candidate. Close
candidates → "which one?" (or all, when the user asks for similar names). No special cases. Candidates come only from
the user's vocabulary, which `ai_vocabulary()` (migration 20261011000000, SECURITY INVOKER) returns as DISTINCT names
under the caller's RLS — 1 call / ~2 KB instead of 5,000 rows / ~770 KB.

**Remarks** are first-class CONTEXT and never FACTS: "what was this for?" answers with the remark, quoted and labelled
as the user's own note (amount/date/merchant always from the record); remark topics ("with friends", "for my birthday",
"related to university", "office er jonno", "untuk birthday") are searched word-by-word (plural-aware); a category
synonym narrower than its category ("rent", "internet", "tuition") uses the remarks that mention it, when any do.
Remarks never change figures, never reach the planner as instructions, and numbers inside them are not accepted as
evidence by the grounding check.

**Speed.** Measured: the deterministic pipeline (plan + tools + compose) takes ~0.4 ms p50 / ~1.2 ms p95 in memory
(see the corpus report). Real latency was the network: functions ran in `iad1` (USA) while Supabase is in Seoul, so
each of ~15–20 sequential round trips crossed the Pacific (3–7 s per answer). Now: functions in `icn1` (Seoul,
`vercel.json`), independent reads in parallel, the same period loaded once per request, the insight read alongside
the total, and a `Server-Timing` header (auth / prepare / answer / save / tools / total — no data) on every answer.

**Corpus and training.** `tests/ai/corpus/` generates (seeded, reproducible) **9,811** quality-controlled examples —
train 5,597 / dev 2,086 / holdout 1,098 / adversarial 1,030 — across English, Banglish, Bengali, Malay and mixed,
30 question families (totals, counts, frequency, averages, largest/smallest, merchants incl. partial/typo references,
categories, accounts, card-vs-QR, comparisons, all-time, specific dates, named months, remark totals/searches,
"what was this for?", follow-ups, casual, security, ambiguity, no-match, insights, weekly, unusual). Splits are
separated by phrasing AND by fixture (different merchants, remarks and amounts for holdout), with exact and
pattern-level leakage checks. Expected results come from an independent oracle over the fixture (integer sen). The
evaluator checks intent, filters, period, figures, evidence, language and security, and attributes each failure to a
stage. Results (`tests/ai/corpus/reports/benchmark-2026-10-08.json`):

| Split | Before (master 13b98bc) | After |
|---|---|---|
| train | 66.8% | 99.6% |
| dev | 60.8% | 99.7% |
| **holdout (first run, untuned)** | 51.0% | **79.4%** |
| **adversarial (first run, untuned)** | 50.4% | **74.1%** |

The train/dev → holdout gap (≈20 points) is real: held-out phrasings for lists ("what X did I buy"), top category and
weekly/insight wording are not generalised yet. Holdout misses were NOT tuned against; a fresh hidden holdout should
be generated for the next iteration. After the run, only security gaps found there were fixed (Malay "kata laluan",
typo'd "system prompt") — no data was exposed by them (they returned no data).

**No model was fine-tuned.** The failures were planner understanding (intent / entity / period), which deterministic,
testable rules fix directly; production runs without an LLM (zero cost), and the deterministic path answers in
~1 ms. The corpus is used for evaluation, planner development and regression testing — not to put private data in a
model. Personal knowledge stays in the user's own memory rules and data (RLS), never in global training.

## 11. Not implemented yet (deliberately)

- **Memory beyond merchant → category** (terminology like "when I say food include cafes", goals, report preferences) and an in-app memory settings screen (today: list/forget by chat).
- **Write actions** (re-categorise, edit): none. Future write tools need explicit confirmation, ownership check, audit log with before/after values.
- **Receipt text / OCR investigation**: receipts are images; OCR text isn't stored, so the AI can only say a receipt exists.
- **Locations**: not recorded by SpenDrop.
- **Recurring payments, duplicates, monthly/yearly reports, budgets/goals, proactive alerts, streaming answers, model routing by size, Android/iOS UI** — the architecture (tool registry, providers, permissions) is ready for them.
- **Answers** are worded in English, Banglish, Bengali or Malay for totals, counts, comparisons, insights and channel answers (same verified figures); other answer types are English. Understanding is lexicon + rules; unusual phrasing falls back to the model (if configured) or a clarifying reply.
- **Proactive notifications** outside the Ask screen (push, weekly scheduled reports) and recurring/duplicate detection.
