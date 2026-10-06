// The Web App must follow the shared SpenDrop contracts in Common/. These tests fail if the Web constants or rules
// drift from the files every platform implements.
import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { ACCOUNT_TYPES, CATEGORIES, COMMON_FUNDING_ACCOUNTS, MAX_PARTS, MOVEMENT_KINDS, PAYMENT_CHANNELS, SPLIT_METHODS } from "@/lib/domain/constants";
import { formatMoney, parseMinor } from "@/lib/domain/money";
import * as split from "@/lib/domain/split";

const common = (file: string) => JSON.parse(readFileSync(path.resolve(__dirname, "../../../Common", file), "utf8"));

describe("Common/Constants", () => {
  it("payment channels match (incl. explicit UNKNOWN default)", () => {
    const c = common("Constants/payment-channels.json");
    expect(PAYMENT_CHANNELS.map(({ id, label, tint }) => ({ id, label, tint }))).toEqual(c.channels.map(({ id, label, tint }: never) => ({ id, label, tint })));
    expect(c.default).toBe("UNKNOWN");
  });
  it("categories match", () => {
    const c = common("Constants/categories.json");
    expect(CATEGORIES).toEqual(c.categories.map(({ id, tint }: never) => ({ id, tint })));
  });
  it("money movement kinds match (direction + PayBook sign)", () => {
    expect(MOVEMENT_KINDS).toEqual(common("Constants/money-movement-kinds.json").kinds);
  });
  it("account types, funding accounts and split methods match", () => {
    const a = common("Constants/account-types.json");
    expect(ACCOUNT_TYPES).toEqual(a.types);
    expect(COMMON_FUNDING_ACCOUNTS).toEqual(a.commonFundingAccounts);
    const s = common("Constants/split-methods.json");
    expect(SPLIT_METHODS).toEqual(s.methods);
    expect(MAX_PARTS).toBe(s.maxParts);
    expect(split.newDraft().autoCalculate).toBe(s.autoCalculateDefault);
  });
});

describe("Common/BusinessRules/money-test-vectors.json", () => {
  const v = common("BusinessRules/money-test-vectors.json");
  it.each(v.parse as [string, number | null][])("parse %j -> %j", (text, minor) => expect(parseMinor(text)).toBe(minor));
  it.each(v.format as [number, string][])("format %j -> %j", (minor, text) => expect(formatMoney(minor)).toBe(text));
});

describe("Common/BusinessRules/split-test-vectors.json", () => {
  const { cases } = common("BusinessRules/split-test-vectors.json");
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  it.each(cases.map((c: { name: string }) => [c.name, c]) as [string, any][])("%s", (_name, c) => {
    let d = split.newDraft();
    for (const [i, name] of (c.people as string[]).entries()) d = split.addPerson(d, { id: `person-${i}`, name });
    if (c.purpose) d = split.setPurpose(d, c.purpose);
    d = split.setMethod(d, c.method, c.total);
    const idOf = (who: string) => d.participants.find((p) => (who === "Me" ? p.isMe : p.name === who))!.id;
    for (const op of c.ops ?? []) {
      if (op.op === "type") d = split.setAmountText(d, idOf(op.who), op.text, c.total);
      if (op.op === "fixed") d = split.setFixed(d, idOf(op.who), op.minor, c.total)!;
      if (op.op === "parts") d = split.setParts(d, idOf(op.who), op.value);
      if (op.op === "autoCalculate") d = split.setAutoCalculate(d, op.value, c.total);
    }
    if (c.expect.shares) {
      expect(split.shares(d, c.total)).toEqual(c.expect.shares);
      expect(c.expect.shares.reduce((a: number, b: number) => a + b, 0)).toBe(c.total);
      expect(split.problem(d, c.total)).toBeNull();
    }
    if (c.expect.problem) expect(split.problem(d, c.total)).toBe(c.expect.problem);
    if (c.expect.remaining !== undefined) expect(split.remainingMinor(d, c.total)).toBe(c.expect.remaining);
  });
});
