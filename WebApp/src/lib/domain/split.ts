// Expense splitting — the same rules as iOS SplitCalculator + SplitDraft (Common/BusinessRules/split-calculation.md).
// All amounts are integer sen. Every successful result adds up EXACTLY to the total.
import { MAX_PARTS } from "./constants";
import { formatMoney, minorToInput, parseMinor } from "./money";
import type { ID, SplitMethod } from "./types";

// ------------------------------------------------------------------------------------------------------------
// SplitCalculator (pure)
// ------------------------------------------------------------------------------------------------------------

export interface CalcParticipant {
  isMe: boolean;
  parts?: number | null;
  enteredMinor?: number | null;
}

export type SplitError =
  | { type: "nonPositiveTotal" }
  | { type: "tooFewParticipants" }
  | { type: "missingMe" }
  | { type: "moreThanOneMe" }
  | { type: "invalidParts"; index: number }
  | { type: "missingAmount"; index: number }
  | { type: "negativeAmount"; index: number }
  /** Positive = shares add up to MORE than the total; negative = less. Never silently adjusted. */
  | { type: "amountsDoNotMatchTotal"; differenceMinor: number };

export type Result<T, E> = { ok: true; value: T } | { ok: false; error: E };
const ok = <T,>(value: T): Result<T, never> => ({ ok: true, value });
const fail = <E,>(error: E): Result<never, E> => ({ ok: false, error });

/**
 * Floor of each proportional share, then the leftover sen one by one to the largest fractional remainders.
 * Ties: Me first (when I paid), then list order. Deterministic.
 */
function largestRemainder(totalMinor: number, weights: number[], participants: CalcParticipant[], iPaid: boolean): number[] {
  const weightSum = weights.reduce((a, b) => a + b, 0);
  const shares = weights.map((w) => Math.floor((totalMinor * w) / weightSum));
  const remainders = weights.map((w) => (totalMinor * w) % weightSum);
  let leftover = totalMinor - shares.reduce((a, b) => a + b, 0);
  const order = participants
    .map((_, i) => i)
    .sort((a, b) => {
      if (remainders[a] !== remainders[b]) return remainders[b] - remainders[a];
      if (iPaid && participants[a].isMe !== participants[b].isMe) return participants[a].isMe ? -1 : 1;
      return a - b;
    });
  let position = 0;
  while (leftover > 0) {
    shares[order[position % order.length]] += 1;
    leftover -= 1;
    position += 1;
  }
  return shares;
}

/**
 * @param iPaid when true, leftover sen from rounding go to Me first so friends never owe an extra sen.
 * @param requireMe false for "paid for someone": the people I paid for share the whole total and I am not in it.
 */
export function calculateSplit(
  totalMinor: number,
  method: SplitMethod,
  participants: CalcParticipant[],
  iPaid = true,
  requireMe = true,
): Result<number[], SplitError> {
  if (!(totalMinor > 0)) return fail({ type: "nonPositiveTotal" });
  if (participants.length < (requireMe ? 2 : 1)) return fail({ type: "tooFewParticipants" });
  const meCount = participants.filter((p) => p.isMe).length;
  if (requireMe) {
    if (meCount === 0) return fail({ type: "missingMe" });
    if (meCount > 1) return fail({ type: "moreThanOneMe" });
  } else if (meCount > 0) {
    return fail({ type: "moreThanOneMe" });
  }
  switch (method) {
    case "equal":
      return ok(largestRemainder(totalMinor, participants.map(() => 1), participants, iPaid));
    case "parts": {
      const weights: number[] = [];
      for (let i = 0; i < participants.length; i++) {
        const parts = participants[i].parts;
        if (parts == null || !Number.isInteger(parts) || parts < 1 || parts > MAX_PARTS) return fail({ type: "invalidParts", index: i });
        weights.push(parts);
      }
      return ok(largestRemainder(totalMinor, weights, participants, iPaid));
    }
    case "amounts": {
      const amounts: number[] = [];
      for (let i = 0; i < participants.length; i++) {
        const entered = participants[i].enteredMinor;
        if (entered == null) return fail({ type: "missingAmount", index: i });
        if (entered < 0) return fail({ type: "negativeAmount", index: i });
        amounts.push(entered);
      }
      const difference = amounts.reduce((a, b) => a + b, 0) - totalMinor;
      if (difference !== 0) return fail({ type: "amountsDoNotMatchTotal", differenceMinor: difference });
      return ok(amounts);
    }
  }
}

// ------------------------------------------------------------------------------------------------------------
// Hybrid Split (pure) — Common/BusinessRules/split-hybrid.md
// ------------------------------------------------------------------------------------------------------------

export interface HybridCalcParticipant {
  isMe: boolean;
  /** Shown in problems ("You" for Me). */
  name: string;
}

/** `blank` = the amount box is empty; `amountMinor` = parsed amount (null when empty or not a number). */
export interface HybridCalcGroup { amountMinor: number | null; blank: boolean; members: number[] }
export interface HybridCalcIndividual { participant: number | null; amountMinor: number | null; blank: boolean }

export type HybridProblem =
  | { type: "nonPositiveTotal" }
  | { type: "tooFewParticipants" }
  | { type: "groupAmount"; group: number }
  | { type: "groupMembers"; group: number }
  | { type: "individualPerson" }
  | { type: "individualAmount"; name: string }
  | { type: "individualDuplicate"; name: string }
  | { type: "nothingFixed" }
  | { type: "exceedTotal"; overMinor: number }
  | { type: "noOneForRemainder"; remainingMinor: number }
  | { type: "personInNoLayer"; name: string };

export interface HybridBreakdown {
  groupAllocationMinor: number;
  individualAllocationMinor: number;
  fixedAllocationMinor: number;
  /** total − fixed allocation (negative when the fixed allocations exceed the total). */
  remainingMinor: number;
  /** Per group (in the order given): what each participant gets from it (all 0 while the group is incomplete). */
  groupShares: number[][];
  /** Per participant: the sum of their group parts, their individual amount, their part of the remaining amount. */
  groupParts: number[];
  individualParts: number[];
  remainingParts: number[];
  /** Final amount per participant (shown live, even while there is a problem). */
  shares: number[];
  allocatedMinor: number;
  /** The first problem in the contract's order, or null when the split can be saved. */
  problem: HybridProblem | null;
}

const positiveMinor = (minor: number | null) => (minor != null && Number.isInteger(minor) && minor > 0 ? minor : null);

/**
 * Group fixed amounts (each a total divided equally between its members), individual fixed amounts (never divided),
 * then what is left divided equally between the remaining group. Every equal division uses the Split Equally rule
 * (largest remainder; ties → Me first when I paid, then participant order). Integer sen only.
 */
export function calculateHybridSplit(
  totalMinor: number,
  participants: HybridCalcParticipant[],
  groups0: HybridCalcGroup[],
  individuals0: HybridCalcIndividual[],
  remaining: number[],
  iPaid = true,
): HybridBreakdown {
  const n = participants.length;
  const zeros = () => participants.map(() => 0);
  const valid = (i: number) => Number.isInteger(i) && i >= 0 && i < n;
  // Rows the user hasn't filled in are ignored (the empty starter group; an empty individual row).
  const groupIndex = groups0.map((g, i) => (g.blank && g.members.length === 0 ? -1 : i));
  const groups = groups0.filter((g) => !(g.blank && g.members.length === 0));
  const individuals = individuals0.filter((r) => !(r.participant === null && r.blank));
  const remainingSet = [...new Set(remaining.filter(valid))].sort((a, b) => a - b);

  const divide = (amount: number, members: number[]) => {
    const out = zeros();
    const list = [...new Set(members.filter(valid))].sort((a, b) => a - b);
    if (amount <= 0 || list.length === 0) return out;
    const parts = largestRemainder(amount, list.map(() => 1), list.map((i) => participants[i]), iPaid);
    list.forEach((index, position) => { out[index] = parts[position]; });
    return out;
  };

  const groupShares = groups0.map((g, i) => {
    const amount = positiveMinor(g.amountMinor);
    return groupIndex[i] < 0 || amount === null ? zeros() : divide(amount, g.members);
  });
  const groupParts = zeros();
  groupShares.forEach((row) => row.forEach((v, i) => { groupParts[i] += v; }));
  const groupAllocationMinor = groupShares.reduce((t, row) => t + row.reduce((a, b) => a + b, 0), 0);
  const individualParts = zeros();
  for (const r of individuals) {
    const amount = positiveMinor(r.amountMinor);
    if (r.participant !== null && valid(r.participant) && amount !== null) individualParts[r.participant] += amount;
  }
  const individualAllocationMinor = individualParts.reduce((a, b) => a + b, 0);
  const fixedAllocationMinor = groupAllocationMinor + individualAllocationMinor;
  const remainingMinor = totalMinor - fixedAllocationMinor;
  const remainingParts = remainingMinor > 0 ? divide(remainingMinor, remainingSet) : zeros();
  const shares = participants.map((_, i) => groupParts[i] + individualParts[i] + remainingParts[i]);
  const allocatedMinor = shares.reduce((a, b) => a + b, 0);

  const nameOf = (i: number) => (participants[i].isMe ? "You" : participants[i].name);
  const problem = ((): HybridProblem | null => {
    if (!(totalMinor > 0)) return { type: "nonPositiveTotal" };
    if (!participants.some((p) => !p.isMe)) return { type: "tooFewParticipants" };
    const numbered = groups0.map((g, i) => ({ g, number: i + 1 })).filter((_, i) => groupIndex[i] >= 0);
    // Group by group (amount, then members), then row by row — the first broken one is named (split-hybrid.md).
    for (const { g, number } of numbered) {
      if (positiveMinor(g.amountMinor) === null) return { type: "groupAmount", group: number };
      if (g.members.filter(valid).length === 0) return { type: "groupMembers", group: number };
    }
    const seen = new Set<number>();
    for (const r of individuals) {
      if (r.participant === null || !valid(r.participant)) return { type: "individualPerson" };
      if (positiveMinor(r.amountMinor) === null) return { type: "individualAmount", name: nameOf(r.participant) };
      if (seen.has(r.participant)) return { type: "individualDuplicate", name: nameOf(r.participant) };
      seen.add(r.participant);
    }
    if (groups.length === 0 && individuals.length === 0) return { type: "nothingFixed" };
    if (fixedAllocationMinor > totalMinor) return { type: "exceedTotal", overMinor: fixedAllocationMinor - totalMinor };
    if (remainingMinor > 0 && remainingSet.length === 0) return { type: "noOneForRemainder", remainingMinor };
    const inLayer = new Set<number>([...groups.flatMap((g) => g.members), ...individuals.map((r) => r.participant!), ...remainingSet]);
    const outside = participants.findIndex((p, i) => !p.isMe && !inLayer.has(i));
    if (outside >= 0) return { type: "personInNoLayer", name: participants[outside].name };
    return null;
  })();
  return {
    groupAllocationMinor, individualAllocationMinor, fixedAllocationMinor, remainingMinor, groupShares, groupParts, individualParts,
    remainingParts, shares, allocatedMinor, problem,
  };
}

/** The exact wording shared by every platform. */
export function hybridMessage(problem: HybridProblem, currency = "RM"): string {
  const money = (minor: number) => formatMoney(Math.abs(minor), currency);
  switch (problem.type) {
    case "nonPositiveTotal": return "Enter the expense amount first.";
    case "tooFewParticipants": return "Add at least one other person.";
    case "groupAmount": return `Enter the amount for group fixed amount ${problem.group}.`;
    case "groupMembers": return `Choose who shares group fixed amount ${problem.group}.`;
    case "individualPerson": return "Choose a person for each individual fixed amount.";
    case "individualAmount": return `Enter the individual fixed amount for ${problem.name}.`;
    case "individualDuplicate": return `${problem.name} already has an individual fixed amount.`;
    case "nothingFixed": return "Add a group fixed amount or an individual fixed amount.";
    case "exceedTotal": return `Fixed allocations exceed the transaction total by ${money(problem.overMinor)}.`;
    case "noOneForRemainder": return `${money(problem.remainingMinor)} is left after the fixed allocations. Choose who shares the remaining amount.`;
    case "personInNoLayer": return `${problem.name} isn't in any part of the split. Add them to an allocation or remove them.`;
  }
}

// ------------------------------------------------------------------------------------------------------------
// SplitDraft (editor state; immutable updates for React)
// ------------------------------------------------------------------------------------------------------------

export interface Participant {
  id: ID;
  personId: ID | null;
  isMe: boolean;
  name: string;
  /** Parts method: 1…99. */
  parts: number;
  /** Amounts: what the user typed. For people Auto Calculate fills in it only mirrors the calculated value. */
  amountText: string;
  /** Amounts + Auto Calculate: base amount added to this person's equal part of the remainder. */
  fixedMinor: number | null;
}

export type Purpose = "shared" | "paidFor";

/** Hybrid Split (purpose Shared only). Member / participant ids are participant ids. */
export interface HybridGroup { id: string; amountText: string; memberIds: ID[] }
export interface HybridIndividual { id: string; participantId: ID | null; amountText: string }
export interface HybridSplit {
  groups: HybridGroup[];
  individuals: HybridIndividual[];
  remainderIds: ID[];
}

export interface SplitDraft {
  method: SplitMethod;
  purpose: Purpose;
  /** Per split only, never a saved preference: every new split starts ON. */
  autoCalculate: boolean;
  /** Me is always first and can never be removed. */
  participants: Participant[];
  /** null = I paid. */
  payerId: ID | null;
  payerName: string | null;
  /** Participants whose amount the user typed, oldest first. */
  typedOrder: ID[];
  /**
   * Hybrid Split: on when set. While on, `method` keeps the method used before (restored when it is turned off).
   * Saved as split method "amounts" plus the expense's split rule.
   */
  hybrid?: HybridSplit | null;
}

export type DraftProblem =
  | { type: "calculator"; error: SplitError }
  | { type: "fixedExceedTotal"; overMinor: number }
  | { type: "noOneForRemainder"; remainingMinor: number }
  | { type: "hybrid"; problem: HybridProblem };

let counter = 0;
const newId = () =>
  typeof crypto !== "undefined" && "randomUUID" in crypto ? crypto.randomUUID() : `p-${Date.now()}-${counter++}`;

export function newDraft(): SplitDraft {
  return {
    method: "equal",
    purpose: "shared",
    autoCalculate: true,
    participants: [{ id: newId(), personId: null, isMe: true, name: "Me", parts: 1, amountText: "", fixedMinor: null }],
    payerId: null,
    payerName: null,
    typedOrder: [],
    hybrid: null,
  };
}

const iPaid = (d: SplitDraft) => d.payerId === null;
export const iPaidForOthers = (d: SplitDraft) => d.purpose === "paidFor" && d.payerId === null;
export const paidForMe = (d: SplitDraft) => d.purpose === "paidFor" && d.payerId !== null;
export const others = (d: SplitDraft) => d.participants.filter((p) => !p.isMe);

/** The people whose shares are calculated: everyone (shared), the people I paid for, or only me. */
export function sharingParticipants(d: SplitDraft): Participant[] {
  if (iPaidForOthers(d)) return others(d);
  if (paidForMe(d)) return d.participants.filter((p) => p.isMe);
  return d.participants;
}

export const containsPerson = (d: SplitDraft, personId: ID) => d.participants.some((p) => p.personId === personId);

export function addPerson(d: SplitDraft, person: { id: ID; name: string }): SplitDraft {
  if (containsPerson(d, person.id)) return d;
  const participant: Participant = { id: newId(), personId: person.id, isMe: false, name: person.name, parts: 1, amountText: "", fixedMinor: null };
  // Hybrid Split on: a new person joins the remaining group only.
  const hybrid = d.hybrid ? { ...d.hybrid, remainderIds: [...d.hybrid.remainderIds, participant.id] } : d.hybrid;
  return { ...d, participants: [...d.participants, participant], hybrid };
}

export function removeParticipant(d: SplitDraft, id: ID): SplitDraft {
  const p = d.participants.find((x) => x.id === id);
  if (!p || p.isMe) return d;
  // Hybrid Split: out of every group, their individual row(s) deleted, out of the remaining group.
  const hybrid = d.hybrid
    ? {
      groups: d.hybrid.groups.map((g) => ({ ...g, memberIds: g.memberIds.filter((x) => x !== id) })),
      individuals: d.hybrid.individuals.filter((r) => r.participantId !== id),
      remainderIds: d.hybrid.remainderIds.filter((x) => x !== id),
    }
    : d.hybrid;
  return { ...d, participants: d.participants.filter((x) => x.id !== id), typedOrder: d.typedOrder.filter((x) => x !== id), hybrid };
}

export function setParts(d: SplitDraft, id: ID, parts: number): SplitDraft {
  return mapParticipant(d, id, (p) => ({ ...p, parts: Math.min(Math.max(Math.round(parts), 1), MAX_PARTS) }));
}

function mapParticipant(d: SplitDraft, id: ID, f: (p: Participant) => Participant): SplitDraft {
  return { ...d, participants: d.participants.map((p) => (p.id === id ? f(p) : p)) };
}

export const isCalculated = (d: SplitDraft, id: ID) =>
  d.autoCalculate && d.method === "amounts" && !paidForMe(d) && !d.typedOrder.includes(id);

/**
 * Sets a typed amount: kept exactly as typed (replaces any fixed amount for that person). Clearing the box hands
 * the person back to Auto Calculate. With Auto Calculate on, when every person now has a typed amount, the one
 * typed longest ago is handed back so the total still works out.
 */
export function setAmountText(d0: SplitDraft, id: ID, text: string, totalMinor?: number): SplitDraft {
  let d = mapParticipant(d0, id, (p) => ({ ...p, amountText: text }));
  d = { ...d, typedOrder: d.typedOrder.filter((x) => x !== id) };
  if (text.trim() === "") return totalMinor == null ? d : refreshCalculatedText(d, totalMinor);
  d = { ...mapParticipant(d, id, (p) => ({ ...p, fixedMinor: null })), typedOrder: [...d.typedOrder, id] };
  if (!d.autoCalculate || d.method !== "amounts" || totalMinor == null) return d;
  const group = sharingParticipants(d);
  if (group.length >= 2 && group.some((p) => p.id === id) && group.every((p) => d.typedOrder.includes(p.id))) {
    const oldest = d.typedOrder.find((t) => t !== id && group.some((p) => p.id === t));
    if (oldest) d = { ...d, typedOrder: d.typedOrder.filter((x) => x !== oldest) };
  }
  return refreshCalculatedText(d, totalMinor);
}

/** Sets (or clears with null) a fixed amount. Negative amounts are refused (returns null). */
export function setFixed(d0: SplitDraft, id: ID, minor: number | null, totalMinor?: number): SplitDraft | null {
  if (!d0.participants.some((p) => p.id === id)) return null;
  if (minor != null && minor < 0) return null;
  let d = mapParticipant(d0, id, (p) => ({ ...p, fixedMinor: minor && minor > 0 ? minor : null }));
  d = { ...d, typedOrder: d.typedOrder.filter((x) => x !== id) };
  return totalMinor == null ? d : refreshCalculatedText(d, totalMinor);
}

/** Turning OFF keeps every amount exactly as shown (they become typed); turning ON recalculates the untyped. */
export function setAutoCalculate(d: SplitDraft, on: boolean, totalMinor: number): SplitDraft {
  if (on === d.autoCalculate) return d;
  let next = d;
  if (!on && d.method === "amounts") {
    const shown = shares(d, totalMinor);
    if (shown) {
      const sharing = new Set(sharingParticipants(d).map((p) => p.id));
      next = { ...d, participants: d.participants.map((p, i) => (sharing.has(p.id) ? { ...p, amountText: minorToInput(shown[i]) } : p)) };
    }
  }
  next = { ...next, autoCalculate: on };
  return on ? refreshCalculatedText(next, totalMinor) : next;
}

export function applyEqualSplit(d: SplitDraft): SplitDraft {
  return { ...d, method: "equal" };
}

/** "Custom Amount": with Auto Calculate on, untyped people are calculated; off, empty boxes start at current shares. */
export function applyCustomAmounts(d: SplitDraft, totalMinor: number): SplitDraft {
  if (d.method === "amounts") return d;
  const current = shares(d, totalMinor);
  let next: SplitDraft = { ...d, method: "amounts" };
  const sharing = new Set(sharingParticipants(next).map((p) => p.id));
  const nothingTyped = next.participants.filter((p) => sharing.has(p.id)).every((p) => (parseMinor(p.amountText) ?? 0) === 0);
  if (current && nothingTyped) {
    next = {
      ...next,
      participants: next.participants.map((p, i) => (sharing.has(p.id) ? { ...p, amountText: minorToInput(current[i]) } : p)),
      typedOrder: [],
    };
  }
  return refreshCalculatedText(next, totalMinor);
}

export function setMethod(d: SplitDraft, method: SplitMethod, totalMinor: number): SplitDraft {
  if (method === "amounts") return applyCustomAmounts(d, totalMinor);
  if (method === "equal") return applyEqualSplit(d);
  return { ...d, method: "parts" };
}

/** "Paid for someone" has no Hybrid Split (choosing it turns Hybrid Split off). */
export function setPurpose(d: SplitDraft, purpose: Purpose): SplitDraft {
  return { ...d, purpose, hybrid: purpose === "shared" ? d.hybrid : null };
}

export function setPayer(d: SplitDraft, payer: { id: ID; name: string } | null): SplitDraft {
  return { ...d, payerId: payer?.id ?? null, payerName: payer?.name ?? null };
}

// ---- Hybrid Split (draft) ----

/** On only for a shared expense. */
export const isHybrid = (d: SplitDraft): boolean => Boolean(d.hybrid) && d.purpose === "shared";

const emptyGroup = (): HybridGroup => ({ id: newId(), amountText: "", memberIds: [] });

/** On: one empty group, no individual amounts, remaining = everyone (Me included). Off: back to the method before. */
export function setHybrid(d: SplitDraft, on: boolean): SplitDraft {
  if (on === isHybrid(d)) return d;
  if (!on) return { ...d, hybrid: null };
  if (d.purpose !== "shared") return d;
  return { ...d, hybrid: { groups: [emptyGroup()], individuals: [], remainderIds: d.participants.map((p) => p.id) } };
}

function mapHybrid(d: SplitDraft, f: (h: HybridSplit) => HybridSplit): SplitDraft {
  return d.hybrid ? { ...d, hybrid: f(d.hybrid) } : d;
}
const hasParticipant = (d: SplitDraft, id: ID) => d.participants.some((p) => p.id === id);
const toggleId = (ids: ID[], id: ID, on: boolean) => (on ? (ids.includes(id) ? ids : [...ids, id]) : ids.filter((x) => x !== id));

export const addHybridGroup = (d: SplitDraft) => mapHybrid(d, (h) => ({ ...h, groups: [...h.groups, emptyGroup()] }));
export const removeHybridGroup = (d: SplitDraft, groupId: string) => mapHybrid(d, (h) => ({ ...h, groups: h.groups.filter((g) => g.id !== groupId) }));
export const setGroupAmount = (d: SplitDraft, groupId: string, text: string) =>
  mapHybrid(d, (h) => ({ ...h, groups: h.groups.map((g) => (g.id === groupId ? { ...g, amountText: text } : g)) }));
export function setGroupMember(d: SplitDraft, groupId: string, id: ID, on: boolean): SplitDraft {
  if (!hasParticipant(d, id)) return d;
  return mapHybrid(d, (h) => ({ ...h, groups: h.groups.map((g) => (g.id === groupId ? { ...g, memberIds: toggleId(g.memberIds, id, on) } : g)) }));
}
export const addIndividual = (d: SplitDraft, participantId: ID | null = null) =>
  mapHybrid(d, (h) => ({ ...h, individuals: [...h.individuals, { id: newId(), participantId, amountText: "" }] }));
export const removeIndividual = (d: SplitDraft, rowId: string) => mapHybrid(d, (h) => ({ ...h, individuals: h.individuals.filter((r) => r.id !== rowId) }));
export function setIndividualPerson(d: SplitDraft, rowId: string, id: ID | null): SplitDraft {
  if (id !== null && !hasParticipant(d, id)) return d;
  return mapHybrid(d, (h) => ({ ...h, individuals: h.individuals.map((r) => (r.id === rowId ? { ...r, participantId: id } : r)) }));
}
export const setIndividualAmount = (d: SplitDraft, rowId: string, text: string) =>
  mapHybrid(d, (h) => ({ ...h, individuals: h.individuals.map((r) => (r.id === rowId ? { ...r, amountText: text } : r)) }));
export function setInRemainder(d: SplitDraft, id: ID, on: boolean): SplitDraft {
  if (!hasParticipant(d, id)) return d;
  return mapHybrid(d, (h) => ({ ...h, remainderIds: toggleId(h.remainderIds, id, on) }));
}

const amountOf = (text: string) => ({ blank: text.trim() === "", amountMinor: text.trim() === "" ? null : parseMinor(text) });

/** The live breakdown of a Hybrid Split (null when it is off). Entries follow `participants`. */
export function hybridBreakdown(d: SplitDraft, totalMinor: number): HybridBreakdown | null {
  const h = d.hybrid;
  if (!h || !isHybrid(d)) return null;
  const position = (id: ID | null) => (id === null ? -1 : d.participants.findIndex((p) => p.id === id));
  return calculateHybridSplit(
    totalMinor,
    d.participants.map((p) => ({ isMe: p.isMe, name: p.isMe ? "You" : p.name })),
    h.groups.map((g) => ({ ...amountOf(g.amountText), members: g.memberIds.map(position).filter((i) => i >= 0) })),
    h.individuals.map((r) => ({ ...amountOf(r.amountText), participant: r.participantId === null || position(r.participantId) < 0 ? null : position(r.participantId) })),
    h.remainderIds.map(position).filter((i) => i >= 0),
    iPaid(d),
  );
}

/** The split method stored on the expense (a Hybrid Split is stored as custom amounts). */
export const savedMethod = (d: SplitDraft): SplitMethod => (isHybrid(d) ? "amounts" : d.method);

/**
 * The expense's split rule: canonical JSON for a valid Hybrid Split (positions = participant order = sort_index),
 * null for every other split. Ignored empty rows are not saved.
 */
export function splitRule(d: SplitDraft, totalMinor: number): string | null {
  const b = hybridBreakdown(d, totalMinor);
  if (!b || b.problem || !d.hybrid) return null;
  const position = (id: ID) => d.participants.findIndex((p) => p.id === id);
  const positions = (ids: ID[]) => [...new Set(ids.map(position).filter((i) => i >= 0))].sort((a, c) => a - c);
  const rule = {
    type: "hybrid",
    version: 1,
    groups: d.hybrid.groups
      .filter((g) => !(g.amountText.trim() === "" && g.memberIds.length === 0))
      .map((g) => ({ amountMinor: parseMinor(g.amountText)!, members: positions(g.memberIds) })),
    individuals: d.hybrid.individuals
      .filter((r) => !(r.participantId === null && r.amountText.trim() === ""))
      .map((r) => ({ participant: position(r.participantId!), amountMinor: parseMinor(r.amountText)! })),
    remaining: positions(d.hybrid.remainderIds),
  };
  return JSON.stringify(rule);
}

/** Reads a saved rule into a Hybrid Split, or null when it isn't a usable hybrid rule for these participants. */
export function parseSplitRule(rule: string | null | undefined, idAtPosition: (position: number) => ID | undefined): HybridSplit | null {
  if (!rule) return null;
  let raw: unknown;
  try { raw = JSON.parse(rule); } catch { return null; }
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;
  if (r.type !== "hybrid" || (r.version !== undefined && r.version !== 1)) return null;
  if (!Array.isArray(r.groups) || !Array.isArray(r.individuals) || !Array.isArray(r.remaining)) return null;
  const isPos = (v: unknown): v is number => Number.isInteger(v) && (v as number) >= 0;
  const isAmount = (v: unknown): v is number => Number.isInteger(v) && (v as number) > 0;
  const idsFor = (list: unknown): ID[] | null => {
    if (!Array.isArray(list) || !list.every(isPos)) return null;
    const ids = list.map((p) => idAtPosition(p));
    return ids.every((x): x is ID => x !== undefined) ? ids : null;
  };
  const groups: HybridGroup[] = [];
  for (const g of r.groups as Record<string, unknown>[]) {
    const memberIds = g && isAmount(g.amountMinor) ? idsFor(g.members) : null;
    if (!memberIds) return null;
    groups.push({ id: newId(), amountText: minorToInput(g.amountMinor as number), memberIds });
  }
  const individuals: HybridIndividual[] = [];
  for (const x of r.individuals as Record<string, unknown>[]) {
    const id = x && isPos(x.participant) && isAmount(x.amountMinor) ? idAtPosition(x.participant) : undefined;
    if (id === undefined) return null;
    individuals.push({ id: newId(), participantId: id, amountText: minorToInput(x.amountMinor as number) });
  }
  const remainderIds = idsFor(r.remaining);
  if (!remainderIds) return null;
  return { groups: groups.length ? groups : [emptyGroup()], individuals, remainderIds };
}

function refreshCalculatedText(d: SplitDraft, totalMinor: number): SplitDraft {
  if (!d.autoCalculate || d.method !== "amounts") return d;
  const result = autoAmounts(d, totalMinor);
  if (!result.ok) return d;
  return { ...d, participants: d.participants.map((p, i) => (isCalculated(d, p.id) ? { ...p, amountText: minorToInput(result.value[i]) } : p)) };
}

/** Typed amounts as typed; total − typed − fixed shared equally by everyone not typed for, plus their fixed amount. */
function autoAmounts(d: SplitDraft, totalMinor: number): Result<number[], DraftProblem> {
  if (!(totalMinor > 0)) return fail({ type: "calculator", error: { type: "nonPositiveTotal" } });
  const group = sharingParticipants(d);
  const requireMe = !iPaidForOthers(d);
  if (group.length < (requireMe ? 2 : 1)) return fail({ type: "calculator", error: { type: "tooFewParticipants" } });
  const result = d.participants.map(() => 0);
  let typedSum = 0;
  const floating: number[] = [];
  for (let g = 0; g < group.length; g++) {
    const p = group[g];
    const index = d.participants.findIndex((x) => x.id === p.id);
    if (isCalculated(d, p.id)) {
      floating.push(index);
    } else {
      const minor = parseMinor(p.amountText);
      if (minor == null) return fail({ type: "calculator", error: { type: "missingAmount", index: g } });
      if (minor < 0) return fail({ type: "calculator", error: { type: "negativeAmount", index: g } });
      result[index] = minor;
      typedSum += minor;
    }
  }
  const fixedSum = floating.reduce((sum, i) => sum + (d.participants[i].fixedMinor ?? 0), 0);
  if (fixedSum > totalMinor) return fail({ type: "fixedExceedTotal", overMinor: fixedSum - totalMinor });
  const remainder = totalMinor - typedSum - fixedSum;
  if (remainder < 0) return fail({ type: "calculator", error: { type: "amountsDoNotMatchTotal", differenceMinor: -remainder } });
  if (floating.length === 0) return remainder === 0 ? ok(result) : fail({ type: "noOneForRemainder", remainingMinor: remainder });
  let parts = floating.map(() => 0);
  if (remainder > 0) {
    const inputs = floating.map((i) => ({ isMe: d.participants[i].isMe }));
    if (inputs.length === 1) {
      parts = [remainder];
    } else {
      const equal = calculateSplit(remainder, "equal", inputs, iPaid(d), inputs.some((x) => x.isMe));
      if (equal.ok) parts = equal.value;
    }
  }
  floating.forEach((index, position) => {
    result[index] = parts[position] + (d.participants[index].fixedMinor ?? 0);
  });
  return ok(result);
}

/** Custom amounts: an empty box is RM 0.00 (what it shows), never "missing"; non-numbers are reported. Same as iOS. */
export const enteredMinor = (text: string) => (text.trim() === "" ? 0 : parseMinor(text));

function plainCalculate(d: SplitDraft, totalMinor: number): Result<number[], SplitError> {
  if (paidForMe(d)) {
    if (!(totalMinor > 0)) return fail({ type: "nonPositiveTotal" });
    return ok(d.participants.map((p) => (p.isMe ? totalMinor : 0)));
  }
  const group = sharingParticipants(d);
  const inputs = group.map((p) => ({ isMe: p.isMe, parts: p.parts, enteredMinor: enteredMinor(p.amountText) }));
  const result = calculateSplit(totalMinor, d.method, inputs, iPaid(d), !iPaidForOthers(d));
  if (!result.ok) return result;
  return ok(d.participants.map((p) => {
    const index = group.findIndex((g) => g.id === p.id);
    return index >= 0 ? result.value[index] : 0;
  }));
}

/** One amount per entry in `participants` (people outside the sharing group get 0). */
export function calculate(d: SplitDraft, totalMinor: number): Result<number[], DraftProblem> {
  const hybrid = hybridBreakdown(d, totalMinor);
  if (hybrid) return hybrid.problem ? fail({ type: "hybrid", problem: hybrid.problem }) : ok(hybrid.shares);
  if (d.method === "amounts" && d.autoCalculate && !paidForMe(d)) return autoAmounts(d, totalMinor);
  const plain = plainCalculate(d, totalMinor);
  return plain.ok ? plain : fail({ type: "calculator", error: plain.error });
}

export function shares(d: SplitDraft, totalMinor: number): number[] | null {
  const result = calculate(d, totalMinor);
  return result.ok ? result.value : null;
}

export function myShareMinor(d: SplitDraft, totalMinor: number): number | null {
  const s = shares(d, totalMinor);
  const me = d.participants.findIndex((p) => p.isMe);
  return s && me >= 0 ? s[me] : null;
}

export function displayAmountText(d: SplitDraft, id: ID, totalMinor: number): string {
  const index = d.participants.findIndex((p) => p.id === id);
  if (index < 0) return "";
  if (!isCalculated(d, id)) return d.participants[index].amountText;
  const result = autoAmounts(d, totalMinor);
  return result.ok ? minorToInput(result.value[index]) : "";
}

export function fixedTotalMinor(d: SplitDraft): number {
  if (!d.autoCalculate || d.method !== "amounts") return 0;
  return sharingParticipants(d).filter((p) => isCalculated(d, p.id)).reduce((s, p) => s + (p.fixedMinor ?? 0), 0);
}

/** What the typed shares add up to (legacy, text only). */
export function assignedMinorTyped(d: SplitDraft): number {
  return sharingParticipants(d).reduce((s, p) => s + (parseMinor(p.amountText) ?? 0), 0);
}

/** What the shares add up to for this total: typed + fixed + the calculated remainder. */
export function assignedMinor(d: SplitDraft, totalMinor: number): number {
  const hybrid = hybridBreakdown(d, totalMinor);
  if (hybrid) return hybrid.allocatedMinor;
  if (d.method !== "amounts") return shares(d, totalMinor)?.reduce((a, b) => a + b, 0) ?? 0;
  if (!d.autoCalculate || paidForMe(d)) return assignedMinorTyped(d);
  const group = sharingParticipants(d);
  const typed = group.filter((p) => !isCalculated(d, p.id)).reduce((s, p) => s + (parseMinor(p.amountText) ?? 0), 0);
  const floating = group.filter((p) => isCalculated(d, p.id));
  const fixed = floating.reduce((s, p) => s + (p.fixedMinor ?? 0), 0);
  return floating.length === 0 ? typed : Math.max(typed + fixed, totalMinor);
}

export const remainingMinor = (d: SplitDraft, totalMinor: number) => totalMinor - assignedMinor(d, totalMinor);

/** A readable problem, or null when the split is valid for this total (same wording as iOS). */
export function problem(d: SplitDraft, totalMinor: number, currency = "RM"): string | null {
  const money = (minor: number) => formatMoney(Math.abs(minor), currency);
  const result = calculate(d, totalMinor);
  if (result.ok) return null;
  const e = result.error;
  if (e.type === "hybrid") return hybridMessage(e.problem, currency);
  if (e.type === "fixedExceedTotal") return `Fixed amounts exceed the expense total by ${money(e.overMinor)}.`;
  if (e.type === "noOneForRemainder")
    return `${money(e.remainingMinor)} remains unassigned. Select at least one participant for the remaining amount (clear someone's amount).`;
  const sharing = sharingParticipants(d);
  switch (e.error.type) {
    case "nonPositiveTotal": return "Enter the expense amount first.";
    case "tooFewParticipants": return iPaidForOthers(d) ? "Choose who you paid for." : "Add at least one other person.";
    case "missingMe":
    case "moreThanOneMe": return "A split must include you exactly once.";
    case "invalidParts": return `Parts must be whole numbers from 1 to ${MAX_PARTS}.`;
    case "missingAmount": {
      const p = sharing[e.error.index];
      return `Enter a valid amount for ${p ? (p.isMe ? "You" : p.name) : "everyone"}.`;
    }
    case "negativeAmount": return `${sharing[e.error.index]?.name ?? "An"}'s amount can't be negative.`;
    case "amountsDoNotMatchTotal":
      return e.error.differenceMinor > 0
        ? `Shares exceed the total by ${money(e.error.differenceMinor)}.`
        : `${money(e.error.differenceMinor)} remains unassigned.`;
  }
}

export const isValid = (d: SplitDraft, totalMinor: number) => problem(d, totalMinor) === null;

/** The share rows to save for an expense (same layout as iOS SplitDraft.apply). Null when invalid. */
export interface ShareRow {
  personId: ID | null; isMe: boolean; nameSnapshot: string; amountMinor: number; parts: number | null; enteredMinor: number | null; sortIndex: number;
}

export function shareRows(d: SplitDraft, totalMinor: number): ShareRow[] | null {
  const amounts = shares(d, totalMinor);
  if (!amounts) return null;
  if (isHybrid(d)) {
    // Saved exactly like a Custom Amount split (entered = final amount); the rule goes on the expense (splitRule).
    return d.participants.map((p, index) => ({
      personId: p.isMe ? null : p.personId, isMe: p.isMe, nameSnapshot: p.isMe ? "Me" : p.name,
      amountMinor: amounts[index], parts: null, enteredMinor: amounts[index], sortIndex: index,
    }));
  }
  const sharing = new Set(sharingParticipants(d).map((p) => p.id));
  const rows: ShareRow[] = [];
  for (let index = 0; index < d.participants.length; index++) {
    const p = d.participants[index];
    // Someone paid entirely for me: only my share is stored. I paid for others: my share is an automatic 0.
    if (paidForMe(d) && !p.isMe) continue;
    const inGroup = sharing.has(p.id);
    rows.push({
      personId: p.isMe ? null : p.personId,
      isMe: p.isMe,
      nameSnapshot: p.isMe ? "Me" : p.name,
      amountMinor: amounts[index],
      parts: d.method === "parts" && inGroup && !paidForMe(d) ? p.parts : null,
      enteredMinor: d.method === "amounts" && inGroup && !paidForMe(d) ? amounts[index] : null,
      sortIndex: index,
    });
  }
  return rows;
}

/** Loads the split saved on an expense (null when not shared). Existing amounts load exactly; Auto Calculate OFF. */
export function draftFromShares(
  expense: { paidByMe: boolean; payerId: ID | null; payerNameSnapshot: string | null; splitMethod: SplitMethod | null; splitRule?: string | null },
  rows: {
    id: ID; personId: ID | null; isMe: boolean; nameSnapshot: string; amountMinor: number; parts: number | null; enteredMinor: number | null; sortIndex: number;
  }[],
  personName: (id: ID) => string | undefined,
): SplitDraft | null {
  if (rows.length === 0) return null;
  const mine = rows.find((r) => r.isMe);
  let purpose: Purpose = "shared";
  if (expense.paidByMe && mine && mine.amountMinor === 0 && mine.enteredMinor == null && mine.parts == null && rows.length > 1) purpose = "paidFor";
  else if (!expense.paidByMe && rows.length === 1 && mine) purpose = "paidFor";
  const ordered = [...rows].sort((a, b) => (a.isMe !== b.isMe ? (a.isMe ? -1 : 1) : a.sortIndex - b.sortIndex));
  const participants: Participant[] = ordered.map((r) => ({
    id: r.id,
    personId: r.isMe ? null : r.personId,
    isMe: r.isMe,
    name: r.isMe ? "Me" : (r.personId && personName(r.personId)) || r.nameSnapshot,
    parts: r.parts ?? 1,
    amountText: minorToInput(r.enteredMinor ?? r.amountMinor),
    fixedMinor: null,
  }));
  if (!participants.some((p) => p.isMe)) participants.unshift({ id: newId(), personId: null, isMe: true, name: "Me", parts: 1, amountText: "", fixedMinor: null });
  // Hybrid Split: the expense's rule, when it parses and every position matches a live share (else: Custom Amount).
  const hybrid = purpose === "shared"
    ? parseSplitRule(expense.splitRule, (position) => {
      const matches = ordered.filter((r) => r.sortIndex === position);
      return matches.length === 1 ? matches[0].id : undefined;
    })
    : null;
  return {
    method: hybrid ? "amounts" : expense.splitMethod ?? "amounts",
    purpose,
    autoCalculate: false,
    participants,
    payerId: expense.paidByMe ? null : expense.payerId,
    payerName: expense.paidByMe ? null : (expense.payerId && personName(expense.payerId)) || expense.payerNameSnapshot,
    typedOrder: [],
    hybrid,
  };
}
