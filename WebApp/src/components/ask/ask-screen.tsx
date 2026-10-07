"use client";

// "Ask SpenDrop": ask anything about your own money. Signed in, questions go to /api/ai/chat (the server derives who
// you are from your session and answers from your records). In the local demo, the same deterministic engine runs
// in this browser over the synthetic demo data — nothing is sent anywhere.
import { ArrowUp, Eye, History, MessageSquarePlus, Sparkles, Trash2 } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";
import { Page, PageHeader } from "@/components/app-shell";
import { useData } from "@/components/providers/data-provider";
import { Button, Card, ErrorBanner, Sheet, Skeleton, cx } from "@/components/ui/primitives";
import { answerDeterministic, capabilitiesAnswer } from "@/lib/ai/core";
import { proactiveNoticesFor, type Notice } from "@/lib/ai/proactive";
import { MemoryRepository, MemoryRuleStore } from "@/lib/ai/repository";
import { localDateOf } from "@/lib/ai/time";
import type { AskAnswer, Focus } from "@/lib/ai/types";
import { isDemoMode } from "@/lib/supabase/config";
import { AnswerView } from "./answer-view";

interface Turn { id: string; role: "user" | "assistant"; text: string; answer?: AskAnswer }
interface Status { provider: string; model: string | null; available: boolean; debug: boolean }

const SUGGESTIONS = [
  "Where did my money go this week?",
  "Where did my RM15 go?",
  "Did I spend more this month?",
  "How much did I spend on food this week?",
  "What was my biggest purchase this month?",
  "Which account do I use most?",
  "What unusual spending happened this week?",
  "Why am I spending so much lately?",
];

const noSubscribe = () => () => {};

const ACTIVITY = ["Checking your transactions…", "Calculating…", "Comparing periods…", "Putting the answer together…"];

const timeZone = () => {
  try { return Intl.DateTimeFormat().resolvedOptions().timeZone; } catch { return "Asia/Kuala_Lumpur"; }
};

export function AskScreen() {
  const { live, source, dataset, status: dataStatus } = useData();
  // Until React is interactive, Enter would submit the form natively and reload the page (losing the question).
  const ready = useSyncExternalStore(noSubscribe, () => true, () => false);
  const [turns, setTurns] = useState<Turn[]>([]);
  const [input, setInput] = useState("");
  const [pending, setPending] = useState(false);
  const [activity, setActivity] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [conversationId, setConversationId] = useState<string | null>(null);
  const [status, setStatus] = useState<Status | null>(null);
  const [historyOpen, setHistoryOpen] = useState(false);
  const [conversations, setConversations] = useState<{ id: string; title: string; updatedAt: string }[] | null>(null);
  const demoFocus = useRef<Focus | null>(null);
  // Demo only: personal rules live in this tab (synthetic data, nothing is sent anywhere).
  const [demoMemory] = useState(() => new MemoryRuleStore());
  const [notices, setNotices] = useState<Notice[]>([]);
  const endRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    if (isDemoMode) return;
    fetch("/api/ai/status").then((r) => (r.ok ? r.json() : null)).then((s) => s && setStatus(s)).catch(() => {});
  }, []);
  useEffect(() => { endRef.current?.scrollIntoView({ behavior: "smooth", block: "end" }); }, [turns, pending]);
  useEffect(() => {
    if (!pending) return;
    const t = window.setInterval(() => setActivity((a) => (a + 1) % ACTIVITY.length), 1400);
    return () => window.clearInterval(t);
  }, [pending]);

  const demoRepo = useMemo(
    () => new MemoryRepository({ expenses: live.expenses, shares: [...live.shares.values()].flat(), movements: live.movements, accounts: live.accounts }, () => [...demoMemory.rules]),
    [live.expenses, live.shares, live.movements, live.accounts, demoMemory],
  );

  const askDemo = useCallback(async (message: string): Promise<AskAnswer> => {
    const tz = timeZone();
    const ctx = { userId: source?.userId ?? "demo", timeZone: tz, today: localDateOf(new Date(), tz), requestId: crypto.randomUUID() };
    const out = await answerDeterministic(message, ctx, demoRepo, demoFocus.current, demoMemory);
    const answer = out.kind === "answer" ? out.answer : capabilitiesAnswer(ctx, out.general);
    if (answer.focus) demoFocus.current = answer.focus;
    return answer;
  }, [demoRepo, demoMemory, source?.userId]);

  // "I noticed…": only meaningful changes against the user's own normal (often there are none, and that's fine).
  useEffect(() => {
    let cancelled = false;
    const tz = timeZone();
    if (isDemoMode) {
      if (!live.expenses.length) return;
      proactiveNoticesFor({ userId: "demo", timeZone: tz, today: localDateOf(new Date(), tz), requestId: "notices" }, demoRepo)
        .then((n) => { if (!cancelled) setNotices(n); }).catch(() => {});
    } else {
      fetch(`/api/ai/insights?tz=${encodeURIComponent(tz)}`).then((r) => (r.ok ? r.json() : null)).then((b) => { if (!cancelled && b?.notices) setNotices(b.notices); }).catch(() => {});
    }
    return () => { cancelled = true; };
  }, [demoRepo, live.expenses.length]);

  const send = useCallback(async (raw: string) => {
    const message = raw.trim();
    if (!message || pending) return;
    setInput("");
    setError(null);
    setTurns((t) => [...t, { id: crypto.randomUUID(), role: "user", text: message }]);
    setPending(true);
    setActivity(0);
    try {
      let answer: AskAnswer;
      if (isDemoMode) {
        answer = await askDemo(message);
      } else {
        const res = await fetch("/api/ai/chat", {
          method: "POST", headers: { "content-type": "application/json" },
          body: JSON.stringify({ message, timeZone: timeZone(), ...(conversationId ? { conversationId } : {}) }),
        });
        const body = await res.json().catch(() => null);
        if (!res.ok) throw new Error(body?.error?.message ?? "I'm having trouble processing that right now. Your financial data is still safe.");
        setConversationId(body.conversationId);
        answer = body.answer;
      }
      setTurns((t) => [...t, { id: crypto.randomUUID(), role: "assistant", text: answer.text, answer }]);
    } catch (e) {
      setError(e instanceof Error && e.message !== "Failed to fetch" ? e.message : "Couldn't reach SpenDrop. Check your connection and try again.");
    } finally {
      setPending(false);
      inputRef.current?.focus();
    }
  }, [askDemo, conversationId, pending]);

  const newConversation = () => {
    setTurns([]); setConversationId(null); setError(null); demoFocus.current = null;
    inputRef.current?.focus();
  };

  const openHistory = async () => {
    setHistoryOpen(true);
    setConversations(null);
    const r = await fetch("/api/ai/conversations").then((x) => x.json()).catch(() => ({ conversations: [] }));
    setConversations(r.conversations ?? []);
  };

  const openConversation = async (id: string) => {
    setHistoryOpen(false);
    setError(null);
    const r = await fetch(`/api/ai/conversations/${id}`);
    if (!r.ok) { setError("That conversation couldn't be opened."); return; }
    const { messages } = (await r.json()) as { messages: { id: string; role: "user" | "assistant"; content: string; answer?: AskAnswer }[] };
    setConversationId(id);
    setTurns(messages.map((m) => ({ id: m.id, role: m.role, text: m.content, answer: m.answer && m.answer.meta ? (m.answer as AskAnswer) : undefined })));
  };

  const deleteConversation = async (id: string) => {
    const r = await fetch(`/api/ai/conversations/${id}`, { method: "DELETE" });
    if (r.ok) {
      setConversations((list) => list?.filter((c) => c.id !== id) ?? null);
      if (id === conversationId) newConversation();
    }
  };

  const empty = turns.length === 0;
  const noData = dataset.expenses.length === 0 && isDemoMode && dataStatus !== "loading" && dataStatus !== "syncing";

  return (
    <>
      <PageHeader
        title="Ask SpenDrop"
        subtitle="Ask anything about your spending"
        actions={
          <>
            {!isDemoMode && <Button variant="secondary" size="sm" onClick={openHistory} aria-label="Previous conversations"><History aria-hidden className="size-4" /><span className="max-sm:sr-only">History</span></Button>}
            {!empty && <Button variant="secondary" size="sm" onClick={newConversation} aria-label="New conversation"><MessageSquarePlus aria-hidden className="size-4" /><span className="max-sm:sr-only">New</span></Button>}
          </>
        }
      />
      <Page className="pb-40 md:pb-36">
        <div className="mx-auto flex w-full max-w-3xl flex-col gap-4">
        {status && status.provider !== "none" && !status.available && (
          <p role="status" className="rounded-[12px] bg-[color-mix(in_srgb,var(--sd-orange)_14%,transparent)] px-3 py-2 text-xs text-label">
            The AI model ({status.provider}{status.model ? ` · ${status.model}` : ""}) isn&apos;t reachable. Questions SpenDrop understands on its own still work.
          </p>
        )}

        {empty && (
          <Card className="sd-rise flex flex-col gap-4">
            <div className="flex items-center gap-3">
              <span className="inline-flex size-11 items-center justify-center rounded-[14px] text-white" style={{ background: "linear-gradient(135deg, var(--sd-accent-fill), var(--sd-indigo))" }}><Sparkles aria-hidden className="size-5" /></span>
              <div>
                <h2 className="font-semibold">Ask anything about your money</h2>
                <p className="text-sm text-label-2">Answers come from your own SpenDrop records — with the transactions to prove it.</p>
              </div>
            </div>
            {noData && <p className="text-sm text-label-2">There are no transactions yet. Add one first, then ask away.</p>}
            {notices.length > 0 && (
              <section aria-label="I noticed" className="flex flex-col gap-2">
                <h3 className="section-header flex items-center gap-1.5"><Eye aria-hidden className="size-3.5" />I noticed</h3>
                {notices.map((n) => (
                  <button key={n.title} type="button" onClick={() => send(n.ask)} className="rounded-[14px] px-4 py-3 text-left hover:opacity-90"
                    style={{ background: "color-mix(in srgb, var(--sd-accent) 9%, transparent)" }}>
                    <span className="block text-[14px] font-semibold">{n.title}</span>
                    <span className="block text-xs text-label-2">{n.detail}</span>
                    <span className="mt-1 block text-xs font-medium text-[var(--sd-accent-text)]">Ask: “{n.ask}”</span>
                  </button>
                ))}
              </section>
            )}
            <div className="flex flex-wrap gap-2">
              {SUGGESTIONS.map((q) => (
                <button key={q} type="button" onClick={() => send(q)} className="rounded-full bg-card-2 px-3.5 py-2 text-left text-[14px] font-medium hover:opacity-80">{q}</button>
              ))}
            </div>
          </Card>
        )}

        <ol className="flex flex-col gap-4" aria-live="polite" aria-label="Conversation">
          {turns.map((t) => (
            <li key={t.id} className={cx("sd-rise flex", t.role === "user" ? "justify-end" : "justify-start")}>
              {t.role === "user" ? (
                <p className="max-w-[85%] whitespace-pre-line rounded-[18px] rounded-br-[6px] bg-[var(--sd-accent-fill)] px-4 py-2.5 text-[15px] text-white">{t.text}</p>
              ) : t.answer?.meta.intent === "SMALL_TALK" ? (
                // Casual replies stay light: a chat bubble, no answer card or evidence.
                <div className="flex max-w-[85%] flex-col items-start gap-2" data-kind="small-talk">
                  <p className="whitespace-pre-line rounded-[18px] rounded-bl-[6px] bg-card px-4 py-2.5 text-[15px] shadow-card">{t.text}</p>
                  {t.answer.followUps.length > 0 && (
                    <div className="flex flex-wrap gap-2">
                      {t.answer.followUps.map((q) => (
                        <button key={q} type="button" onClick={() => send(q)} className="rounded-full border border-separator px-3 py-1.5 text-[13px] font-medium text-[var(--sd-accent-text)] hover:bg-card-2">{q}</button>
                      ))}
                    </div>
                  )}
                </div>
              ) : (
                <Card className="w-full max-w-full">
                  {t.answer ? <AnswerView answer={t.answer} onFollowUp={send} debug={status?.debug} /> : <p className="whitespace-pre-line text-[15px]">{t.text}</p>}
                </Card>
              )}
            </li>
          ))}
          {pending && (
            <li className="flex" role="status">
              <Card className="flex w-full items-center gap-3">
                <Sparkles aria-hidden className="size-4 animate-pulse text-[var(--sd-accent-text)]" />
                <span className="text-sm text-label-2">{ACTIVITY[activity]}</span>
                <Skeleton className="ml-auto h-3 w-16" />
              </Card>
            </li>
          )}
        </ol>
        {error && <ErrorBanner message={error} />}
        <div ref={endRef} />
        </div>
      </Page>

      {/* Composer: above the phone tab bar, at the bottom on larger screens */}
      <form
        onSubmit={(e) => { e.preventDefault(); send(input); }}
        className="fixed inset-x-0 bottom-[calc(64px+env(safe-area-inset-bottom))] z-30 bg-[linear-gradient(to_top,var(--sd-bg)_75%,transparent)] px-4 pb-3 pt-4 md:sticky md:bottom-0 md:px-8 md:pb-5"
      >
        <div className="mx-auto flex max-w-3xl items-end gap-2 rounded-[22px] border border-separator bg-card/90 p-2 shadow-card backdrop-blur-xl">
          <label htmlFor="ask-input" className="sr-only">Ask anything about your money</label>
          <textarea
            id="ask-input" ref={inputRef} rows={1} value={input} maxLength={500} placeholder={ready ? "Ask anything about your money…" : "Loading…"} disabled={!ready}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) { e.preventDefault(); send(input); } }}
            className="max-h-32 min-h-10 flex-1 resize-none bg-transparent px-3 py-2 text-[16px] text-label placeholder:text-label-3 focus:outline-none"
          />
          <button type="submit" disabled={!ready || !input.trim() || pending} aria-label="Ask"
            className="inline-flex size-10 shrink-0 items-center justify-center rounded-full bg-[var(--sd-accent-fill)] text-white transition-opacity disabled:opacity-40">
            <ArrowUp aria-hidden className="size-5" />
          </button>
        </div>
        <p className="mx-auto mt-1.5 max-w-3xl px-2 text-center text-[11px] text-label-2">
          SpenDrop AI reads only your own records and never changes them. It describes your data — it isn&apos;t financial advice.
        </p>
      </form>

      <Sheet open={historyOpen} onClose={() => setHistoryOpen(false)} title="Previous conversations">
        {conversations === null ? (
          <div className="flex flex-col gap-2">{[0, 1, 2].map((i) => <Skeleton key={i} className="h-10" />)}</div>
        ) : conversations.length === 0 ? (
          <p className="text-sm text-label-2">No conversations yet.</p>
        ) : (
          <ul className="flex flex-col">
            {conversations.map((c) => (
              <li key={c.id} className="flex items-center gap-2 border-b border-separator last:border-0">
                <button type="button" onClick={() => openConversation(c.id)} className="min-w-0 flex-1 py-3 text-left">
                  <span className="block truncate font-medium">{c.title}</span>
                  <span className="block text-xs text-label-2">{new Intl.DateTimeFormat("en-MY", { dateStyle: "medium", timeStyle: "short" }).format(new Date(c.updatedAt))}</span>
                </button>
                <button type="button" onClick={() => deleteConversation(c.id)} aria-label={`Delete ${c.title}`} className="inline-flex size-9 items-center justify-center rounded-full text-label-2 hover:bg-card-2 hover:text-red">
                  <Trash2 aria-hidden className="size-4" />
                </button>
              </li>
            ))}
          </ul>
        )}
      </Sheet>
    </>
  );
}
