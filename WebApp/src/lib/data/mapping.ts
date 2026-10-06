// Cloud rows use snake_case columns (Supabase); the app uses camelCase records. One generic, lossless mapping.
import type { Dataset, TableName } from "@/lib/domain/types";

export const toSnake = (key: string) => key.replace(/[A-Z]/g, (c) => `_${c.toLowerCase()}`);
export const toCamel = (key: string) => key.replace(/_([a-z])/g, (_, c: string) => c.toUpperCase());

export function rowToRecord<T>(row: Record<string, unknown>): T {
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(row)) {
    if (key === "user_id" || key === "server_updated_at") continue;
    out[toCamel(key)] = typeof value === "string" && /^-?\d+$/.test(value) && key.endsWith("_minor") ? Number(value) : value;
  }
  return out as T;
}

export function recordToRow(record: object): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(record)) out[toSnake(key)] = value === undefined ? null : value;
  return out;
}

/** Which Dataset list each cloud table fills. Order = safe write order (parents before children). */
export const TABLES: { table: TableName; key: keyof Dataset }[] = [
  { table: "accounts", key: "accounts" },
  { table: "people", key: "people" },
  { table: "person_payment_methods", key: "paymentMethods" },
  { table: "expenses", key: "expenses" },
  { table: "expense_shares", key: "shares" },
  { table: "money_movements", key: "movements" },
  { table: "settlement_allocations", key: "allocations" },
  { table: "classification_rules", key: "classificationRules" },
  { table: "channel_rules", key: "channelRules" },
];
