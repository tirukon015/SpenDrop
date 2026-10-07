"use client";

import { Minus, Pin, Search, UserPlus } from "lucide-react";
import { useMemo, useState } from "react";
import { Avatar, Button, Card, Divider, Field, Input, Segmented, Select, Sheet, Toggle, cx } from "@/components/ui/primitives";
import { formatMoney, minorToInput, parseMinor } from "@/lib/domain/money";
import * as S from "@/lib/domain/split";
import type { ID, Person, SplitMethod } from "@/lib/domain/types";

/** Pick an existing PayBook person or create a new one (saved with the transaction). */
export function PersonPicker({ open, onClose, people, exclude, onPick, onCreate, title = "Add Person" }: {
  open: boolean; onClose: () => void; people: Person[]; exclude: ID[]; onPick: (p: Person) => void; onCreate: (name: string) => void; title?: string;
}) {
  const [query, setQuery] = useState("");
  const q = query.trim().toLowerCase();
  const matches = people.filter((p) => !p.isArchived && !exclude.includes(p.id) && (!q || p.name.toLowerCase().includes(q)));
  const exact = people.some((p) => p.name.trim().toLowerCase() === q);
  return (
    <Sheet open={open} onClose={() => { setQuery(""); onClose(); }} title={title}>
      <div className="flex flex-col gap-3">
        <div className="relative">
          <Search aria-hidden className="pointer-events-none absolute left-3.5 top-1/2 size-4 -translate-y-1/2 text-label-2" />
          <label htmlFor="person-search" className="sr-only">Search or type a new name</label>
          <Input id="person-search" autoFocus className="pl-10" placeholder="Search or type a new name" value={query} onChange={(e) => setQuery(e.target.value)} />
        </div>
        {q && !exact && (
          <Button variant="tinted" onClick={() => { onCreate(query.trim()); setQuery(""); onClose(); }}>
            <UserPlus aria-hidden className="size-4" /> New Person “{query.trim()}”
          </Button>
        )}
        <Card className="overflow-hidden p-0">
          {matches.length === 0 ? (
            <p className="p-4 text-center text-sm text-label-2">{people.length === 0 ? "Your PayBook is empty — type a name to add someone." : "No matching people."}</p>
          ) : matches.map((p, i) => (
            <div key={p.id}>
              {i > 0 && <Divider inset={64} />}
              <button type="button" onClick={() => { onPick(p); setQuery(""); onClose(); }} className="flex min-h-12 w-full items-center gap-3 px-4 py-2 text-left hover:bg-card-2">
                <Avatar name={p.name} size={36} />
                <span className="font-medium">{p.name}</span>
                {p.isFrequent && <span className="ml-auto text-xs text-label-2">Frequent</span>}
              </button>
            </div>
          ))}
        </Card>
      </div>
    </Sheet>
  );
}

function FixedAmountSheet({ participant, onClose, onSave }: { participant: S.Participant | null; onClose: () => void; onSave: (minor: number | null) => void }) {
  const [text, setText] = useState("");
  const parsed = parseMinor(text);
  const valid = parsed !== null && parsed >= 0;
  const name = participant?.isMe ? "You" : participant?.name ?? "";
  return (
    <Sheet open={participant !== null} onClose={onClose} title={`${name} · Fixed Amount`}
      footer={
        <div className="flex gap-2">
          {participant?.fixedMinor != null && <Button variant="destructive" onClick={() => { onSave(null); onClose(); }}>Remove</Button>}
          <Button variant="secondary" className="ml-auto" onClick={onClose}>Cancel</Button>
          <Button disabled={!valid} onClick={() => { onSave(parsed); onClose(); }}>Save</Button>
        </div>
      }>
      <div className="flex flex-col gap-3" key={participant?.id}>
        <p className="text-sm text-label-2">Added to {participant?.isMe ? "your" : `${name}'s`} equal share of what&apos;s left of the total.</p>
        <label className="sr-only" htmlFor="fixed-amount">Fixed amount</label>
        <div className="flex items-center gap-2 rounded-field bg-card px-4 shadow-card">
          <span className="text-label-2">RM</span>
          <input id="fixed-amount" inputMode="decimal" autoFocus defaultValue={participant?.fixedMinor ? minorToInput(participant.fixedMinor) : ""}
            onChange={(e) => setText(e.target.value)} placeholder="0.00" className="min-h-12 flex-1 bg-transparent text-xl font-semibold focus:outline-none" />
        </div>
        {text && !valid && <p role="alert" className="text-xs text-orange">Enter an amount of RM 0.00 or more.</p>}
      </div>
    </Sheet>
  );
}

/** A participant checkbox (Hybrid Split: group members and who shares the remaining amount). */
function MemberCheck({ id, label, checked, onChange }: { id: string; label: string; checked: boolean; onChange: (on: boolean) => void }) {
  return (
    <label htmlFor={id} className={cx("flex min-h-11 cursor-pointer items-center gap-2.5 rounded-[12px] px-3 py-2 text-[15px] transition-colors",
      checked ? "bg-[color-mix(in_srgb,var(--sd-blue)_12%,transparent)] font-medium" : "bg-card-2 text-label-2 hover:text-label")}>
      <input id={id} type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)}
        className="size-[18px] shrink-0 cursor-pointer accent-[var(--sd-blue)]" />
      <span className="min-w-0 truncate">{label}</span>
    </label>
  );
}

/** An amount box with the currency in front (same look as the other split amount boxes). */
function MoneyInput({ id, value, onChange, label, invalid, className }: {
  id: string; value: string; onChange: (text: string) => void; label?: string; invalid?: boolean; className?: string;
}) {
  return (
    <div className={cx("flex items-center gap-2 rounded-field bg-card-2 px-3.5", invalid && "outline outline-1 outline-[var(--sd-orange)]", className)}>
      <span aria-hidden className="text-label-2">RM</span>
      <input id={id} inputMode="decimal" autoComplete="off" placeholder="0.00" value={value} aria-label={label} aria-invalid={invalid}
        onChange={(e) => onChange(e.target.value.replace(/[^\d.,]/g, ""))}
        className="tabular min-h-11 w-full min-w-0 bg-transparent text-[17px] font-semibold placeholder:text-label-3 focus:outline-none" />
    </div>
  );
}

const amountInvalid = (text: string) => text.trim() !== "" && !((parseMinor(text) ?? 0) > 0);

/**
 * Hybrid Split (Common/BusinessRules/split-hybrid.md): group fixed amounts (a total divided equally between the group),
 * individual fixed amounts (one person each, not divided), and the remaining amount split equally. Live.
 */
function HybridSections({ draft, onChange, breakdown, currency }: {
  draft: S.SplitDraft; onChange: (d: S.SplitDraft) => void; breakdown: S.HybridBreakdown; currency: string;
}) {
  const h = draft.hybrid!;
  const money = (m: number) => formatMoney(m, currency);
  const label = (p: S.Participant) => (p.isMe ? "You" : p.name);
  const indexOf = (id: ID) => draft.participants.findIndex((p) => p.id === id);
  const sharingCount = h.remainderIds.length;
  return (
    <section aria-label="Hybrid Split" className="flex flex-col gap-4">
      <section aria-labelledby="group-fixed-heading" className="flex flex-col gap-1.5">
        <h3 id="group-fixed-heading" className="section-header px-1">Group fixed amount</h3>
        {h.groups.map((g, n) => {
          const name = `Group fixed amount ${n + 1}`;
          const share = breakdown.groupShares[n] ?? [];
          const members = draft.participants.filter((p) => g.memberIds.includes(p.id));
          const allocation = share.reduce((a, b) => a + b, 0);
          return (
            <Card key={g.id} as="div" aria-label={name} className="flex flex-col gap-3">
              <div className="flex items-center justify-between gap-2">
                <span className="text-sm font-semibold">{h.groups.length > 1 ? `Group ${n + 1}` : "Group"}</span>
                <Button type="button" variant="secondary" size="sm" onClick={() => onChange(S.removeHybridGroup(draft, g.id))} aria-label={`Remove group ${n + 1}`}>Remove</Button>
              </div>
              <div className="flex flex-col gap-1.5">
                <label htmlFor={`group-amount-${g.id}`} className="text-sm font-medium">Amount (total for the group)</label>
                <MoneyInput id={`group-amount-${g.id}`} value={g.amountText} invalid={amountInvalid(g.amountText)}
                  onChange={(text) => onChange(S.setGroupAmount(draft, g.id, text))} />
              </div>
              <fieldset className="flex flex-col gap-1.5">
                <legend className="mb-1.5 text-sm font-medium">Divide this amount between</legend>
                <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
                  {draft.participants.map((p) => (
                    <MemberCheck key={p.id} id={`group-${g.id}-${p.id}`} label={label(p)} checked={g.memberIds.includes(p.id)}
                      onChange={(on) => onChange(S.setGroupMember(draft, g.id, p.id, on))} />
                  ))}
                </div>
              </fieldset>
              {members.length > 0 && allocation > 0 && (
                <ul className="flex flex-wrap gap-x-4 gap-y-1 text-sm" aria-label={`${name} per person`}>
                  {members.map((p) => <li key={p.id}><span className="text-label-2">{label(p)}</span> <span className="tabular font-medium">{money(share[indexOf(p.id)] ?? 0)}</span></li>)}
                </ul>
              )}
              <p className="flex justify-between rounded-[10px] bg-card-2 px-3 py-2 text-sm">
                <span className="text-label-2">Group allocation</span><span className="tabular font-medium">{money(allocation)}</span>
              </p>
            </Card>
          );
        })}
        <Button type="button" variant="tinted" size="sm" className="self-start" onClick={() => onChange(S.addHybridGroup(draft))}>
          + {h.groups.length ? "Add Another Group" : "Add Group"}
        </Button>
      </section>

      <section aria-labelledby="individual-fixed-heading" className="flex flex-col gap-1.5">
        <h3 id="individual-fixed-heading" className="section-header px-1">Individual fixed amounts</h3>
        <Card className="flex flex-col gap-3">
          {h.individuals.length === 0 && <p className="text-sm text-label-2">An amount for one person only (not divided).</p>}
          {h.individuals.map((r, n) => (
            <div key={r.id} className="flex flex-wrap items-center gap-2 sm:flex-nowrap">
              <Select aria-label={`Person for individual fixed amount ${n + 1}`} value={r.participantId ?? ""} className="min-w-0 flex-1 basis-40"
                onChange={(e) => onChange(S.setIndividualPerson(draft, r.id, e.target.value || null))}>
                <option value="">Choose person…</option>
                {draft.participants.map((p) => <option key={p.id} value={p.id}>{label(p)}</option>)}
              </Select>
              <MoneyInput id={`individual-${r.id}`} label={`Individual fixed amount ${n + 1}`} value={r.amountText} invalid={amountInvalid(r.amountText)}
                className="min-w-0 flex-1 basis-28 sm:max-w-40" onChange={(text) => onChange(S.setIndividualAmount(draft, r.id, text))} />
              <Button type="button" variant="secondary" size="sm" onClick={() => onChange(S.removeIndividual(draft, r.id))} aria-label={`Remove individual fixed amount ${n + 1}`}>Remove</Button>
            </div>
          ))}
          <Button type="button" variant="tinted" size="sm" className="self-start" onClick={() => onChange(S.addIndividual(draft))}>+ Add Individual Fixed Amount</Button>
          <p className="flex justify-between rounded-[10px] bg-card-2 px-3 py-2 text-sm">
            <span className="text-label-2">Individual allocation</span><span className="tabular font-medium">{money(breakdown.individualAllocationMinor)}</span>
          </p>
        </Card>
      </section>

      <section aria-labelledby="remaining-heading" className="flex flex-col gap-1.5">
        <h3 id="remaining-heading" className="section-header px-1">Remaining amount</h3>
        <Card className="flex flex-col gap-3">
          <div className="flex items-baseline justify-between gap-2">
            <span className="text-sm text-label-2">Left after fixed allocations</span>
            <span className={cx("tabular text-[17px] font-semibold", breakdown.remainingMinor < 0 && "text-orange")} aria-live="polite" data-testid="hybrid-remaining">
              {breakdown.remainingMinor < 0 ? `−${money(-breakdown.remainingMinor)}` : money(breakdown.remainingMinor)}
            </span>
          </div>
          <fieldset className="flex flex-col gap-1.5">
            <legend className="mb-1.5 text-sm font-medium">Split remaining between</legend>
            <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
              {draft.participants.map((p) => (
                <MemberCheck key={p.id} id={`remainder-${p.id}`} label={label(p)} checked={h.remainderIds.includes(p.id)}
                  onChange={(on) => onChange(S.setInRemainder(draft, p.id, on))} />
              ))}
            </div>
          </fieldset>
          <p className="flex flex-wrap justify-between gap-x-2 text-xs text-label-2">
            <span className="font-semibold text-green">Auto Calculate: ON</span>
            <span>{breakdown.remainingMinor > 0 && sharingCount > 0 ? `Split equally between ${sharingCount} ${sharingCount === 1 ? "person" : "people"}` : "Split equally"}</span>
          </p>
        </Card>
      </section>
    </section>
  );
}

/** How a person's final amount is made up: "RM 50.00 group + RM 20.00 individual + RM 26.66 remaining". */
function hybridRowDetail(d: S.SplitDraft, b: S.HybridBreakdown, index: number, money: (m: number) => string): string {
  const p = d.participants[index];
  const h = d.hybrid!;
  const parts: string[] = [];
  if (h.groups.some((g) => g.memberIds.includes(p.id))) parts.push(`${money(b.groupParts[index])} group`);
  if (h.individuals.some((r) => r.participantId === p.id)) parts.push(`${money(b.individualParts[index])} individual`);
  if (h.remainderIds.includes(p.id)) parts.push(`${money(b.remainingParts[index])} remaining`);
  return parts.length ? parts.join(" + ") : "Not included";
}

export function SplitEditor({ draft, onChange, totalMinor, currency, people, onCreatePerson }: {
  draft: S.SplitDraft; onChange: (d: S.SplitDraft) => void; totalMinor: number; currency: string; people: Person[];
  onCreatePerson: (name: string) => Person;
}) {
  const [picker, setPicker] = useState<"participant" | "payer" | null>(null);
  const [fixedFor, setFixedFor] = useState<S.Participant | null>(null);
  const amounts = S.shares(draft, totalMinor);
  const hybridOn = S.isHybrid(draft);
  const breakdown = S.hybridBreakdown(draft, totalMinor);
  const problem = S.problem(draft, totalMinor, currency);
  const mine = S.myShareMinor(draft, totalMinor);
  const money = (m: number) => formatMoney(m, currency);
  const fixedAvailable = !hybridOn && draft.method === "amounts" && draft.autoCalculate && draft.purpose === "shared";
  const allocated = S.assignedMinor(draft, totalMinor);
  const remaining = totalMinor - allocated;
  const paidForMe = S.paidForMe(draft);
  const visible = paidForMe ? draft.participants.filter((p) => p.isMe) : S.iPaidForOthers(draft) ? S.others(draft) : draft.participants;
  const frequent = useMemo(() => people.filter((p) => p.isFrequent && !p.isArchived && !S.containsPerson(draft, p.id)), [people, draft]);

  const preview = useMemo(() => {
    if (!amounts) return [];
    if (draft.payerId) {
      const me = draft.participants.findIndex((p) => p.isMe);
      return amounts[me] > 0 ? [`You owe ${draft.payerName ?? "them"} ${money(amounts[me])}`] : [];
    }
    return draft.participants.flatMap((p, i) => (!p.isMe && amounts[i] > 0 ? [`${p.name} owes you ${money(amounts[i])}`] : []));
  }, [amounts, draft]); // eslint-disable-line react-hooks/exhaustive-deps

  const methods: { id: SplitMethod; label: string }[] = [{ id: "equal", label: "Split Equally" }, { id: "amounts", label: "Custom Amount" }];
  if (draft.method === "parts") methods.push({ id: "parts", label: "Parts" });

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between text-[15px]">
        <span className="text-label-2">Total</span>
        <span className="tabular font-semibold">{money(totalMinor)}</span>
      </div>

      <Segmented label="Split type" size="sm" value={draft.purpose}
        onChange={(purpose) => onChange(S.setPurpose(draft, purpose))}
        options={[{ id: "shared", label: "Shared Expense" }, { id: "paidFor", label: "Paid for Someone" }]} />

      {draft.purpose === "shared" && (
        <Toggle id="hybrid-split-toggle" checked={hybridOn} onChange={(on) => onChange(S.setHybrid(draft, on))}
          label="Hybrid Split"
          description="Group fixed amounts, individual fixed amounts, and the rest split equally." />
      )}

      {!paidForMe && !hybridOn && (
        <Segmented label="Split method" value={draft.method} onChange={(m) => onChange(S.setMethod(draft, m, totalMinor))} options={methods} />
      )}

      {hybridOn && breakdown && <HybridSections draft={draft} onChange={onChange} breakdown={breakdown} currency={currency} />}

      {draft.purpose === "paidFor" && (
        <p className="text-xs text-label-2">{paidForMe ? "Someone paid the whole amount for you: it's all your share." : "You paid the whole amount for the people below. Your share is RM 0.00."}</p>
      )}

      <div>
        <p className="section-header mb-1.5 px-1">{paidForMe ? "For" : S.iPaidForOthers(draft) ? "Paid for" : hybridOn ? "Final calculation" : "Split between"}</p>
        <Card className="overflow-hidden p-0">
          {visible.map((p, rowIndex) => {
            const index = draft.participants.findIndex((x) => x.id === p.id);
            const calculated = S.isCalculated(draft, p.id);
            const label = p.isMe ? "You" : p.name;
            return (
              <div key={p.id}>
                {rowIndex > 0 && <Divider inset={60} />}
                <div className="flex min-h-14 items-center gap-2.5 px-3 py-2">
                  <Avatar name={p.isMe ? "Me" : p.name} size={34} />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-[15px] font-medium">{label}
                      {((p.isMe && !draft.payerId) || (draft.payerId && draft.payerId === p.personId)) && <span className="ml-1.5 text-[11px] font-normal text-label-2">paid</span>}
                    </p>
                    {fixedAvailable && p.fixedMinor != null && <p className="text-[11px] text-label-2">{money(p.fixedMinor)} fixed + equal share</p>}
                    {breakdown && <p className="text-xs text-label-2">{hybridRowDetail(draft, breakdown, index, money)}</p>}
                  </div>
                  {breakdown ? (
                    <span className="tabular text-[15px] font-medium">{money(breakdown.shares[index])}</span>
                  ) : paidForMe ? (
                    <span className="tabular text-label-2">{money(totalMinor)}</span>
                  ) : draft.method === "equal" ? (
                    <span className="tabular text-label-2">{amounts ? money(amounts[index]) : "—"}</span>
                  ) : draft.method === "parts" ? (
                    <div className="flex items-center gap-1.5">
                      <button type="button" aria-label={`Fewer parts for ${label}`} onClick={() => onChange(S.setParts(draft, p.id, p.parts - 1))} className="size-8 rounded-full bg-card-2 font-semibold">−</button>
                      <span className="w-6 text-center tabular" aria-live="polite">{p.parts}×</span>
                      <button type="button" aria-label={`More parts for ${label}`} onClick={() => onChange(S.setParts(draft, p.id, p.parts + 1))} className="size-8 rounded-full bg-card-2 font-semibold">+</button>
                      <span className="tabular w-24 text-right text-sm text-label-2">{amounts ? money(amounts[index]) : "—"}</span>
                    </div>
                  ) : (
                    <>
                      {fixedAvailable && (
                        <button type="button" onClick={() => setFixedFor(p)} aria-label={`Fixed amount for ${p.isMe ? "you" : p.name}`}
                          className={cx("inline-flex size-9 items-center justify-center rounded-full", p.fixedMinor != null ? "text-blue" : "text-label-2 hover:text-label")}>
                          {p.fixedMinor != null ? <Pin aria-hidden className="size-4 fill-current" /> : <Pin aria-hidden className="size-4" />}
                        </button>
                      )}
                      <label htmlFor={`amount-${p.id}`} className="sr-only">{p.isMe ? "Your" : `${p.name}'s`} amount</label>
                      <input
                        id={`amount-${p.id}`}
                        inputMode="decimal"
                        value={calculated ? "" : p.amountText}
                        placeholder={calculated ? S.displayAmountText(draft, p.id, totalMinor) || "0.00" : "0.00"}
                        onChange={(e) => onChange(S.setAmountText(draft, p.id, e.target.value, totalMinor))}
                        className={cx("tabular h-10 w-28 rounded-[10px] bg-card-2 px-2.5 text-right text-[16px] focus:outline-2 focus:outline-[var(--sd-accent)]",
                          calculated ? "placeholder:text-label-2" : "placeholder:text-label-3")}
                      />
                    </>
                  )}
                  {!p.isMe && (
                    <button type="button" aria-label={`Remove ${p.name}`} onClick={() => onChange(S.removeParticipant(draft, p.id))}
                      className="inline-flex size-9 items-center justify-center rounded-full text-red hover:bg-card-2">
                      <Minus aria-hidden className="size-4 rounded-full bg-red p-0.5 text-white" />
                    </button>
                  )}
                </div>
              </div>
            );
          })}
        </Card>
      </div>

      {!paidForMe && frequent.length > 0 && (
        <div className="-mx-1 flex gap-1.5 overflow-x-auto px-1" aria-label="Frequent people">
          {frequent.map((p) => (
            <button key={p.id} type="button" onClick={() => onChange(S.addPerson(draft, p))}
              className="shrink-0 rounded-full bg-[color-mix(in_srgb,var(--sd-blue)_12%,transparent)] px-3 py-1.5 text-xs font-semibold text-blue">+ {p.name}</button>
          ))}
        </div>
      )}
      {!paidForMe && (
        <Button variant="tinted" onClick={() => setPicker("participant")} className="self-start"><UserPlus aria-hidden className="size-4" /> Add Person</Button>
      )}

      {draft.method === "amounts" && !paidForMe && !hybridOn && (
        <Toggle id="auto-calc" checked={draft.autoCalculate} onChange={(on) => onChange(S.setAutoCalculate(draft, on, totalMinor))}
          label="Auto Calculate" description={draft.autoCalculate ? "What's left is shared equally by everyone you haven't typed an amount for." : "Nothing is changed for you. The amounts must add up to the total."} />
      )}

      <Card className="flex flex-col gap-2 text-[15px]">
        {fixedAvailable && S.fixedTotalMinor(draft) > 0 && (
          <>
            <div className="flex justify-between"><span className="text-label-2">Fixed</span><span className="tabular">{money(S.fixedTotalMinor(draft))}</span></div>
            <div className="flex justify-between"><span className="text-label-2">Shared equally</span>
              <span className="tabular">{money(Math.max(0, totalMinor - S.fixedTotalMinor(draft) - draft.participants.filter((p) => !S.isCalculated(draft, p.id) && S.sharingParticipants(draft).some((x) => x.id === p.id)).reduce((t, p) => t + (parseMinor(p.amountText) ?? 0), 0)))}</span></div>
          </>
        )}
        <div className="flex justify-between"><span className="text-label-2">Total allocated</span><span className="tabular">{money(allocated)}</span></div>
        <div className="flex justify-between font-semibold">
          <span className="text-label-2">Remaining</span>
          <span className={cx("tabular", remaining === 0 ? "text-green" : "text-orange")} aria-live="polite">{remaining < 0 ? `−${money(-remaining)}` : money(remaining)}</span>
        </div>
      </Card>

      <Field label="Paid by" htmlFor="paid-by">
        <Select id="paid-by" value={draft.payerId ?? ""}
          onChange={(e) => {
            if (e.target.value === "__other") return setPicker("payer");
            const person = people.find((p) => p.id === e.target.value);
            onChange(S.setPayer(draft, person ? { id: person.id, name: person.name } : null));
          }}>
          <option value="">Me</option>
          {[...new Map([...S.others(draft).filter((p) => p.personId).map((p) => [p.personId!, p.name] as const),
            ...(draft.payerId ? [[draft.payerId, draft.payerName ?? ""] as const] : [])]).entries()]
            .map(([id, name]) => <option key={id} value={id}>{name}</option>)}
          <option value="__other">Someone else…</option>
        </Select>
      </Field>

      <div aria-live="polite">
        {problem ? (
          <p role="alert" className="rounded-field bg-[color-mix(in_srgb,var(--sd-orange)_12%,transparent)] p-3 text-sm text-label">{problem}</p>
        ) : (
          <div className="flex flex-col gap-0.5 text-sm">
            {mine !== null && <p className="text-label-2">✓ Balanced · Your share {money(mine)}</p>}
            {preview.map((line) => <p key={line} className="font-semibold">{line}</p>)}
            {draft.payerId && mine !== null && <p className="text-xs text-label-2">{draft.payerName} paid. Nothing left your account.</p>}
          </div>
        )}
      </div>

      <PersonPicker open={picker !== null} onClose={() => setPicker(null)} people={people} title={picker === "payer" ? "Who paid?" : "Add Person"}
        exclude={picker === "payer" ? [] : draft.participants.map((p) => p.personId).filter((x): x is ID => Boolean(x))}
        onPick={(p) => onChange(picker === "payer" ? S.setPayer(draft, p) : S.addPerson(draft, p))}
        onCreate={(name) => { const p = onCreatePerson(name); onChange(picker === "payer" ? S.setPayer(draft, p) : S.addPerson(draft, p)); }} />
      <FixedAmountSheet participant={fixedFor} onClose={() => setFixedFor(null)}
        onSave={(minor) => { if (fixedFor) { const next = S.setFixed(draft, fixedFor.id, minor, totalMinor); if (next) onChange(next); } }} />
    </div>
  );
}

