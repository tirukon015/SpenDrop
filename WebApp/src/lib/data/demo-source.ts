"use client";

// Local demo backend (NEXT_PUBLIC_SPENDROP_DEMO=1 only): behaves like the Supabase tables + functions, but keeps
// synthetic data in this browser. Used for development and browser testing without a Supabase project. The UI
// always shows a "Demo" banner. Never used for real accounts.
import type { NewAllocation, NewPayment } from "@/lib/domain/ledger";
import type { Expense, ExpenseShare, TableName } from "@/lib/domain/types";
import { recordToRow } from "./mapping";
import { DataError, type BackupMeta, type DataSource, type PulledRows } from "./source";

const KEY = "spendrop-demo-v1";
type Tables = Record<TableName, Record<string, Record<string, unknown>>>;
const TABLE_NAMES: TableName[] = [
  "accounts", "people", "person_payment_methods", "expenses", "expense_shares", "money_movements", "settlement_allocations",
  "classification_rules", "channel_rules",
];

let clock = 0;
/** Strictly increasing server time (like server_updated_at). */
function serverNow() {
  clock = Math.max(clock + 1, Date.now());
  return new Date(clock).toISOString();
}

function empty(): Tables {
  return Object.fromEntries(TABLE_NAMES.map((t) => [t, {}])) as Tables;
}

export class DemoSource implements DataSource {
  readonly kind = "demo" as const;
  readonly userId = "00000000-0000-4000-8000-000000000000";
  readonly email = "demo@spendrop.local";
  readonly provider = "demo";
  private tables: Tables;
  private receipts = new Map<string, string>();

  constructor() {
    this.tables = this.load() ?? this.seed();
  }

  private load(): Tables | null {
    try {
      const raw = localStorage.getItem(KEY);
      return raw ? ({ ...empty(), ...JSON.parse(raw) } as Tables) : null;
    } catch {
      return null;
    }
  }

  private persist() {
    try {
      localStorage.setItem(KEY, JSON.stringify(this.tables));
    } catch {
      // storage full or blocked: demo keeps working in memory
    }
  }

  private put(table: TableName, row: Record<string, unknown>) {
    const current = this.tables[table][row.id as string];
    if (current && typeof current.updated_at === "string" && typeof row.updated_at === "string" && current.updated_at > row.updated_at) return;
    this.tables[table][row.id as string] = { ...current, ...row, server_updated_at: serverNow() };
  }

  async pull(table: TableName, since: string | null): Promise<PulledRows> {
    await tick();
    const rows = Object.values(this.tables[table])
      .filter((r) => !since || (r.server_updated_at as string) > since)
      .sort((a, b) => ((a.server_updated_at as string) < (b.server_updated_at as string) ? -1 : 1));
    return { rows: structuredClone(rows), cursor: rows.at(-1)?.server_updated_at as string ?? since };
  }

  async upsert(table: TableName, rows: Record<string, unknown>[]) {
    await tick();
    for (const row of rows) this.put(table, row);
    this.persist();
  }

  async saveExpense(expense: Expense, shares: Omit<ExpenseShare, "expenseId" | "deletedAt">[]) {
    await tick();
    const live = shares.reduce((t, s) => t + s.amountMinor, 0);
    if (shares.length > 0 && live !== expense.amountMinor) throw new DataError("The split doesn't add up to the amount.", "validation");
    this.put("expenses", recordToRow(expense));
    const keep = new Set(shares.map((s) => s.id));
    for (const row of Object.values(this.tables.expense_shares)) {
      if (row.expense_id === expense.id && !row.deleted_at && !keep.has(row.id as string))
        this.put("expense_shares", { ...row, deleted_at: expense.updatedAt, updated_at: expense.updatedAt });
    }
    for (const s of shares) this.put("expense_shares", { ...recordToRow(s), expense_id: expense.id, deleted_at: null, updated_at: expense.updatedAt });
    this.persist();
  }

  async recordSettlement(payments: NewPayment[], allocations: (NewAllocation & { id: string })[]) {
    await tick();
    const now = new Date().toISOString();
    for (const p of payments) {
      this.put("money_movements", {
        id: p.id, kind: p.kind, direction: p.kind === "repaymentReceived" ? "in" : "out", amount_minor: p.amountMinor, currency: p.currency,
        date: p.date, person_id: p.personId, person_name_snapshot: p.personName, linked_expense_id: null, linked_expense_snapshot: null,
        account_id: p.accountId, counter_account_id: null, note: p.note, transaction_reference: null, source_type: "manual",
        payment_channel: "UNKNOWN", created_at: now, updated_at: now, deleted_at: null,
      });
    }
    for (const a of allocations) this.put("settlement_allocations", { ...recordToRow(a), created_at: now, updated_at: now, deleted_at: null });
    this.persist();
  }

  async uploadReceipt(file: Blob, expenseId: string) {
    const path = `${this.userId}/${expenseId}/${crypto.randomUUID()}.webp`;
    this.receipts.set(path, URL.createObjectURL(file));
    return path;
  }

  async receiptUrl(path: string) {
    return this.receipts.get(path) ?? null;
  }

  async removeReceipt(path: string) {
    this.receipts.delete(path);
  }

  async listBackups(): Promise<BackupMeta[]> {
    return [];
  }

  async downloadBackup(): Promise<unknown> {
    throw new DataError("The demo has no cloud backups. Use “Import a backup file” instead.", "validation");
  }

  async signOut() {}

  async deleteAccount() {
    this.tables = empty();
    try {
      localStorage.removeItem(KEY);
    } catch {}
  }

  /** Synthetic, anonymised sample data (no real people or transactions). */
  private seed(): Tables {
    this.tables = empty();
    const now = Date.now();
    const day = 86_400_000;
    const at = (daysAgo: number, hour = 12) => {
      const d = new Date(now - daysAgo * day);
      d.setHours(hour, 15, 0, 0);
      return d.toISOString();
    };
    const meta = (daysAgo: number) => ({ created_at: at(daysAgo), updated_at: at(daysAgo), deleted_at: null });
    const uid = () => crypto.randomUUID();

    const accounts = [
      { id: uid(), name: "Maybank", type: "bank" },
      { id: uid(), name: "Touch 'n Go", type: "eWallet" },
      { id: uid(), name: "Cash", type: "cash" },
    ];
    accounts.forEach((a, i) => this.put("accounts", { ...a, currency: "RM", icon: null, is_archived: false, sort_index: i, ...meta(60) }));
    const people = ["Aisyah", "Daniel", "Mei Ling"].map((name, i) => ({ id: uid(), name, notes: null, is_frequent: i < 2, is_archived: false, ...meta(50) }));
    people.forEach((p) => this.put("people", p));
    this.put("person_payment_methods", {
      id: uid(), person_id: people[0].id, payment_type: "E-Wallet", provider: "Touch 'n Go", custom_provider_name: null,
      account_identifier: "012-345 6789", label: "Personal", notes: null, ...meta(50),
    });

    const plain: [string, string, string, string, number, number][] = [
      ["Tealive", "Food", "DUITNOW_QR", "Touch 'n Go", 990, 0],
      ["Jaya Grocer", "Groceries", "CARD", "Maybank", 8645, 1],
      ["Shell", "Transport", "CARD", "Maybank", 6000, 2],
      ["Nasi Kandar Pelita", "Food", "DUITNOW_QR", "Touch 'n Go", 1850, 3],
      ["Unifi", "Bills", "BANK_TRANSFER", "Maybank", 12900, 5],
      ["Watsons", "Health", "CARD", "Maybank", 4590, 6],
      ["Grab", "Transport", "E_WALLET", "Touch 'n Go", 1720, 8],
      ["Netflix", "Subscription", "CARD", "Maybank", 5500, 10],
      ["Uniqlo", "Shopping", "APPLE_PAY", "Maybank", 7990, 12],
      ["Kedai Runcit", "Groceries", "CASH", "Cash", 1240, 14],
      ["TGV Cinemas", "Entertainment", "CARD", "Maybank", 3600, 18],
      ["Popular Bookstore", "Education", "CARD", "Maybank", 4250, 24],
      ["Tealive", "Food", "TNG_QR", "Touch 'n Go", 1090, 33],
      ["Lotus's", "Groceries", "CARD", "Maybank", 15330, 38],
      ["Parking", "Transport", "UNKNOWN", "Unknown", 400, 41],
    ];
    const accountId = (name: string) => accounts.find((a) => a.name === name)?.id ?? null;
    for (const [merchant, category, channel, funding, amount, daysAgo] of plain) {
      this.put("expenses", {
        id: uid(), amount_minor: amount, currency: "RM", merchant, category, payment_channel: channel, funding_account: funding,
        funding_instrument: null, account_id: accountId(funding), payment_source: null, date: at(daysAgo, 9 + (daysAgo % 10)), notes: null,
        transaction_reference: null, source_type: "manual", paid_by_me: true, payer_id: null, payer_name_snapshot: null, split_method: null,
        receipt_path: null, is_sample_data: false, ...meta(daysAgo),
      });
    }
    // A shared dinner I paid (Aisyah owes 40, Daniel owes 35) and a taxi Daniel paid for me.
    const dinner = uid();
    this.put("expenses", {
      id: dinner, amount_minor: 10000, currency: "RM", merchant: "Restoran Selera Kampung", category: "Food", payment_channel: "DUITNOW_QR",
      funding_account: "Maybank", funding_instrument: null, account_id: accounts[0].id, payment_source: null, date: at(4, 20), notes: "Team dinner",
      transaction_reference: null, source_type: "manual", paid_by_me: true, payer_id: null, payer_name_snapshot: null, split_method: "amounts",
      receipt_path: null, is_sample_data: false, ...meta(4),
    });
    [[null, true, "Me", 2500], [people[0].id, false, "Aisyah", 4000], [people[1].id, false, "Daniel", 3500]].forEach(([pid, isMe, name, amount], i) =>
      this.put("expense_shares", { id: uid(), expense_id: dinner, person_id: pid, is_me: isMe, name_snapshot: name, amount_minor: amount, parts: null,
        entered_minor: amount, sort_index: i, ...meta(4) }));
    const taxi = uid();
    this.put("expenses", {
      id: taxi, amount_minor: 2400, currency: "RM", merchant: "Grab", category: "Transport", payment_channel: "UNKNOWN", funding_account: "Unknown",
      funding_instrument: null, account_id: null, payment_source: null, date: at(7, 23), notes: null, transaction_reference: null, source_type: "manual",
      paid_by_me: false, payer_id: people[1].id, payer_name_snapshot: "Daniel", split_method: "amounts", receipt_path: null, is_sample_data: false, ...meta(7),
    });
    this.put("expense_shares", { id: uid(), expense_id: taxi, person_id: null, is_me: true, name_snapshot: "Me", amount_minor: 2400, parts: null,
      entered_minor: null, sort_index: 0, ...meta(7) });

    const movement = (kind: string, direction: string, amount: number, daysAgo: number, extra: Record<string, unknown> = {}) =>
      this.put("money_movements", {
        id: uid(), kind, direction, amount_minor: amount, currency: "RM", date: at(daysAgo, 10), person_id: null, person_name_snapshot: null,
        linked_expense_id: null, linked_expense_snapshot: null, account_id: accounts[0].id, counter_account_id: null, note: null,
        transaction_reference: null, source_type: "manual", payment_channel: "BANK_TRANSFER", ...meta(daysAgo), ...extra,
      });
    movement("income", "in", 450000, 6, { note: "Salary" });
    movement("income", "in", 420000, 36, { note: "Salary" });
    movement("ownTransfer", "internal", 20000, 9, { counter_account_id: accounts[1].id, note: "Top up" });
    movement("loanGiven", "out", 5000, 15, { person_id: people[2].id, person_name_snapshot: "Mei Ling", note: "Concert tickets" });
    this.persist();
    return this.tables;
  }
}

const tick = () => new Promise((r) => setTimeout(r, 0));
