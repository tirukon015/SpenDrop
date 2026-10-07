// Brings an iPhone backup (the JSON the iOS app writes locally and to its cloud backup) into the cloud records.
// Explicit user action only — never automatic. Same rules as iOS restore: records keep their ids (no duplicates),
// accounts with the same name are merged, a record that is newer in the cloud is kept, nothing is deleted.
// Sample data is skipped unless the user asks for it. Pure function: returns the rows to write + a summary.
import { MOVEMENT_KINDS, isCategory, isChannel } from "@/lib/domain/constants";
import type {
  Account, ChannelRule, ClassificationRule, Dataset, Expense, ExpenseShare, MoneyMovement, MovementKind, Person,
  PersonPaymentMethod, SettlementAllocation,
} from "@/lib/domain/types";

type Json = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any

export interface ImportSummary {
  version: number;
  exportDate: string | null;
  added: Record<string, number>;
  updated: Record<string, number>;
  keptNewer: number;
  skippedSample: number;
  missingReferences: number;
  accountsMergedByName: number;
}

export interface ImportPlan {
  summary: ImportSummary;
  records: Dataset;
}

const id = (value: unknown): string | null => (typeof value === "string" && value.length > 0 ? value.toLowerCase() : null);
const iso = (value: unknown, fallback: string): string => (typeof value === "string" && !Number.isNaN(Date.parse(value)) ? new Date(value).toISOString() : fallback);
const normalizedName = (name: string) => name.trim().toLowerCase().replace(/\s+/g, " ");
/** iOS Money.minorUnits(from:) — amount × 100 rounded to nearest, ties away from zero. */
const minorFromAmount = (amount: number) => Math.sign(amount) * Math.round(Math.abs(amount) * 100);

export function validateBackup(payload: unknown): Json {
  if (!payload || typeof payload !== "object") throw new Error("This isn't a SpenDrop backup file.");
  const p = payload as Json;
  if (!Array.isArray(p.expenses) || !Array.isArray(p.paybookProfiles) || typeof p.version !== "number")
    throw new Error("This isn't a SpenDrop backup file.");
  if (p.version < 1 || p.version > 4) throw new Error(`This backup was made by a newer SpenDrop (format ${p.version}). Update the app first.`);
  return p;
}

export function planBackupImport(payload: unknown, existing: Dataset, opts: { includeSample?: boolean; now?: string } = {}): ImportPlan {
  const p = validateBackup(payload);
  const now = opts.now ?? new Date().toISOString();
  const summary: ImportSummary = {
    version: p.version, exportDate: typeof p.exportDate === "string" ? p.exportDate : null,
    added: {}, updated: {}, keptNewer: 0, skippedSample: 0, missingReferences: 0, accountsMergedByName: 0,
  };
  const records: Dataset = {
    accounts: [], people: [], paymentMethods: [], expenses: [], shares: [], movements: [], allocations: [], classificationRules: [], channelRules: [],
  };
  const sampleIds = new Set<string>((p.sampleRecords ?? []).map((r: Json) => id(r.recordID)).filter(Boolean));
  const isSample = (recordId: string | null, flag?: boolean) => !opts.includeSample && (flag === true || (recordId !== null && sampleIds.has(recordId)));

  const byId = <T extends { id: string; updatedAt: string }>(list: T[]) => new Map(list.map((r) => [r.id, r]));
  const existingMaps = {
    accounts: byId(existing.accounts), people: byId(existing.people), paymentMethods: byId(existing.paymentMethods),
    expenses: byId(existing.expenses), movements: byId(existing.movements), allocations: byId(existing.allocations),
    classificationRules: byId(existing.classificationRules), channelRules: byId(existing.channelRules),
  };
  /** Adds a record unless the cloud already has a newer version. */
  function take<T extends { id: string; updatedAt: string }>(key: keyof typeof existingMaps, list: T[], record: T) {
    const current = existingMaps[key].get(record.id);
    if (current && current.updatedAt > record.updatedAt) {
      summary.keptNewer += 1;
      return false;
    }
    list.push(record);
    const bucket = current ? summary.updated : summary.added;
    bucket[key] = (bucket[key] ?? 0) + 1;
    return true;
  }

  // Accounts (merged by name like iOS AccountLinker: same name = same account, no duplicate)
  const accountIdMap = new Map<string, string>();
  const accountsByName = new Map(existing.accounts.filter((a) => !a.deletedAt).map((a) => [normalizedName(a.name), a.id]));
  for (const a of (p.accounts ?? []) as Json[]) {
    const aid = id(a.id);
    if (!aid || typeof a.name !== "string" || !a.name.trim()) continue;
    if (isSample(aid)) { summary.skippedSample += 1; continue; }
    const sameName = accountsByName.get(normalizedName(a.name));
    if (sameName && sameName !== aid) {
      accountIdMap.set(aid, sameName);
      summary.accountsMergedByName += 1;
      continue;
    }
    accountIdMap.set(aid, aid);
    accountsByName.set(normalizedName(a.name), aid);
    const created = iso(a.createdAt, now);
    take("accounts", records.accounts, {
      id: aid, name: a.name.trim().slice(0, 80), type: ["bank", "eWallet", "cash", "other"].includes(a.typeRaw) ? a.typeRaw : "other",
      currency: a.currency || "RM", icon: a.icon ?? null, isArchived: Boolean(a.isArchived), sortIndex: Number(a.sortIndex) || 0,
      createdAt: created, updatedAt: created, deletedAt: null,
    } satisfies Account);
  }
  const knownAccounts = new Set([...existing.accounts.map((a) => a.id), ...records.accounts.map((a) => a.id)]);
  const accountRef = (value: unknown) => {
    const raw = id(value);
    if (!raw) return null;
    const mapped = accountIdMap.get(raw) ?? raw;
    if (knownAccounts.has(mapped)) return mapped;
    summary.missingReferences += 1;
    return null;
  };

  // People + payment methods
  for (const person of (p.paybookProfiles ?? []) as Json[]) {
    const pid = id(person.id);
    if (!pid || typeof person.name !== "string") continue;
    if (isSample(pid)) { summary.skippedSample += 1; continue; }
    const created = iso(person.createdAt, now);
    take("people", records.people, {
      id: pid, name: person.name.trim().slice(0, 80) || "Unnamed", notes: person.notes ?? null, isFrequent: Boolean(person.isFrequent),
      isArchived: Boolean(person.isArchived), createdAt: created, updatedAt: iso(person.updatedAt, created), deletedAt: null,
    } satisfies Person);
    for (const m of (person.paymentMethods ?? []) as Json[]) {
      const mid = id(m.id);
      if (!mid) continue;
      const mCreated = iso(m.createdAt, created);
      take("paymentMethods", records.paymentMethods, {
        id: mid, personId: pid, paymentType: ["Bank Account", "E-Wallet", "Payment ID", "Other"].includes(m.paymentTypeRaw) ? m.paymentTypeRaw : "Other",
        provider: m.provider ?? "", customProviderName: m.customProviderName ?? null, accountIdentifier: String(m.accountIdentifier ?? "").slice(0, 120),
        label: m.label ?? null, notes: m.notes ?? null, createdAt: mCreated, updatedAt: iso(m.updatedAt, mCreated), deletedAt: null,
      } satisfies PersonPaymentMethod);
    }
  }
  const knownPeople = new Set([...existing.people.map((x) => x.id), ...records.people.map((x) => x.id)]);
  const personRef = (value: unknown) => {
    const raw = id(value);
    if (!raw) return null;
    if (knownPeople.has(raw)) return raw;
    summary.missingReferences += 1;
    return null;
  };

  // Expenses + shares
  for (const e of p.expenses as Json[]) {
    const eid = id(e.id);
    if (!eid || typeof e.amount !== "number") continue;
    if (isSample(eid, e.isSampleData)) { summary.skippedSample += 1; continue; }
    const amountMinor = minorFromAmount(e.amount);
    if (amountMinor <= 0) continue;
    const created = iso(e.createdAt, now);
    const payerId = personRef(e.payerId);
    const paidByMe = e.paidByMe !== false || (!payerId && !e.payerNameSnapshot);
    const shares = ((e.shares ?? []) as Json[])
      .map((s): ExpenseShare | null => {
        const sid = id(s.id);
        if (!sid || typeof s.amountMinor !== "number") return null;
        return {
          id: sid, expenseId: eid, personId: s.isMe ? null : personRef(s.personId), isMe: Boolean(s.isMe), nameSnapshot: s.nameSnapshot ?? "",
          amountMinor: s.amountMinor, parts: s.parts ?? null, enteredMinor: s.enteredMinor ?? null, sortIndex: Number(s.sortIndex) || 0,
          createdAt: created, updatedAt: iso(e.updatedAt, created), deletedAt: null,
        };
      })
      .filter((s): s is ExpenseShare => s !== null);
    // Only keep a split whose shares add up exactly (a broken split is imported as a normal expense).
    const validSplit = shares.length > 0 && shares.reduce((t, s) => t + s.amountMinor, 0) === amountMinor;
    // Hybrid Split rule (optional; older backups have none and load exactly as before).
    const splitRule = validSplit && typeof e.splitRule === "string" && e.splitRule.length > 0 && e.splitRule.length <= 4000 ? e.splitRule : null;
    const added = take("expenses", records.expenses, {
      id: eid, amountMinor, currency: e.currency || "RM", merchant: String(e.merchant ?? "Unknown").slice(0, 200) || "Unknown",
      category: isCategory(e.categoryRaw) ? e.categoryRaw : "Other",
      paymentChannel: isChannel(e.paymentChannelRaw ?? "") ? e.paymentChannelRaw : "UNKNOWN",
      fundingAccount: String(e.fundingAccount ?? "Unknown").slice(0, 80) || "Unknown", fundingInstrument: e.fundingInstrument ?? null,
      accountId: accountRef(e.accountId), paymentSource: e.paymentSourceRaw ?? null, date: iso(e.date, created), notes: e.notes ?? null,
      transactionReference: e.transactionReference ?? null, sourceType: e.sourceTypeRaw ?? "manual", paidByMe,
      payerId: paidByMe ? null : payerId, payerNameSnapshot: paidByMe ? null : (e.payerNameSnapshot ?? null),
      splitMethod: validSplit && ["equal", "parts", "amounts"].includes(e.splitMethodRaw) ? e.splitMethodRaw : null,
      receiptPath: null, isSampleData: Boolean(e.isSampleData), createdAt: created, updatedAt: iso(e.updatedAt, created), deletedAt: null,
      ...(splitRule ? { splitRule } : {}),
    } satisfies Expense);
    if (added && validSplit) records.shares.push(...shares);
  }
  const knownExpenses = new Set([...existing.expenses.map((x) => x.id), ...records.expenses.map((x) => x.id)]);

  // Money movements
  for (const m of (p.moneyMovements ?? []) as Json[]) {
    const mid = id(m.id);
    if (!mid || typeof m.amountMinor !== "number" || m.amountMinor <= 0) continue;
    if (isSample(mid)) { summary.skippedSample += 1; continue; }
    const kind = MOVEMENT_KINDS.find((k) => k.id === m.kindRaw);
    if (!kind) continue;
    const created = iso(m.createdAt, now);
    const linked = id(m.linkedExpenseId);
    take("movements", records.movements, {
      id: mid, kind: kind.id as MovementKind, direction: kind.direction, amountMinor: m.amountMinor, currency: m.currency || "RM",
      date: iso(m.date, created), personId: personRef(m.personId), personNameSnapshot: m.personNameSnapshot ?? null,
      linkedExpenseId: linked && knownExpenses.has(linked) ? linked : null, linkedExpenseSnapshot: m.linkedExpenseSnapshot ?? null,
      accountId: accountRef(m.accountId), counterAccountId: accountRef(m.counterAccountId), note: m.note ?? null,
      transactionReference: m.transactionReference ?? null, sourceType: m.sourceTypeRaw ?? "manual",
      paymentChannel: isChannel(m.paymentChannelRaw ?? "") ? m.paymentChannelRaw : "UNKNOWN",
      createdAt: created, updatedAt: iso(m.updatedAt, created), deletedAt: null,
    } satisfies MoneyMovement);
  }
  const knownMovements = new Set([...existing.movements.map((x) => x.id), ...records.movements.map((x) => x.id)]);

  // Settlement allocations (only when their person and references exist)
  for (const a of (p.settlementAllocations ?? []) as Json[]) {
    const aid = id(a.id);
    const personId = id(a.personID);
    if (!aid || !personId || !knownPeople.has(personId) || typeof a.amountMinor !== "number" || a.amountMinor <= 0) continue;
    if (isSample(aid)) { summary.skippedSample += 1; continue; }
    const ref = (value: unknown, known: Set<string>) => { const r = id(value); return r && known.has(r) ? r : null; };
    const created = iso(a.createdAt, now);
    take("allocations", records.allocations, {
      id: aid, groupId: id(a.groupID) ?? aid, kind: ["payment", "assign", "offset"].includes(a.kindRaw) ? a.kindRaw : "payment",
      paymentId: ref(a.paymentID, knownMovements), expenseId: ref(a.expenseID, knownExpenses), loanId: ref(a.loanID, knownMovements),
      personId, direction: a.direction === -1 ? -1 : 1, amountMinor: a.amountMinor, currency: a.currency || "RM", date: iso(a.date, created),
      createdAt: created, updatedAt: created, deletedAt: null,
    } satisfies SettlementAllocation);
  }

  // Learned rules
  const ruleKeys = new Set(existing.classificationRules.filter((r) => !r.deletedAt).map((r) => r.merchantKey));
  for (const r of (p.classificationRules ?? []) as Json[]) {
    const rid = id(r.id);
    if (!rid || typeof r.merchantKey !== "string" || ruleKeys.has(r.merchantKey) && !existingMaps.classificationRules.has(rid)) continue;
    const created = iso(r.createdAt, now);
    take("classificationRules", records.classificationRules, {
      id: rid, merchantKey: r.merchantKey, category: isCategory(r.categoryRaw ?? "") ? r.categoryRaw : null, suggestedType: r.suggestedTypeRaw ?? null,
      accountId: accountRef(r.accountId), hitCount: Number(r.hitCount) || 1, createdAt: created, updatedAt: iso(r.updatedAt, created), deletedAt: null,
    } satisfies ClassificationRule);
  }
  const channelKeys = new Set(existing.channelRules.filter((r) => !r.deletedAt).map((r) => `${r.merchantKey}|${r.fundingKey}`));
  for (const r of (p.channelRules ?? []) as Json[]) {
    const rid = id(r.id);
    if (!rid || typeof r.merchantKey !== "string" || !isChannel(r.channelRaw ?? "")) continue;
    if (channelKeys.has(`${r.merchantKey}|${r.fundingKey ?? ""}`) && !existingMaps.channelRules.has(rid)) continue;
    const created = iso(r.createdAt, now);
    take("channelRules", records.channelRules, {
      id: rid, merchantKey: r.merchantKey, fundingKey: r.fundingKey ?? "", channel: r.channelRaw, hitCount: Number(r.hitCount) || 1,
      createdAt: created, updatedAt: iso(r.updatedAt, created), deletedAt: null,
    } satisfies ChannelRule);
  }
  return { summary, records };
}
