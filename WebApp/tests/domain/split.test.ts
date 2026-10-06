import { describe, expect, it } from "vitest";
import * as s from "@/lib/domain/split";

const three = (total: number) => {
  let d = s.newDraft();
  d = s.addPerson(d, { id: "v", name: "Vijay" });
  d = s.addPerson(d, { id: "r", name: "Riyadh" });
  return s.setMethod(d, "amounts", total);
};
const id = (d: s.SplitDraft, name: string) => d.participants.find((p) => (name === "Me" ? p.isMe : p.name === name))!.id;

describe("split editor rules (same as iOS)", () => {
  it("every new split starts with Auto Calculate ON; turning it OFF affects only that draft", () => {
    const first = s.newDraft();
    const off = s.setAutoCalculate(three(20000), false, 20000);
    expect(first.autoCalculate).toBe(true);
    expect(off.autoCalculate).toBe(false);
    expect(s.newDraft().autoCalculate).toBe(true);
  });

  it("turning Auto Calculate OFF freezes the amounts shown; nothing changes by itself afterwards", () => {
    const off = s.setAutoCalculate(three(20000), false, 20000);
    expect(off.participants.map((p) => p.amountText)).toEqual(["66.67", "66.67", "66.66"]);
    const typed = s.setAmountText(off, id(off, "Me"), "70", 20000);
    expect(typed.participants.map((p) => p.amountText)).toEqual(["70", "66.67", "66.66"]);
  });

  it("recalculates when the total or a fixed amount changes", () => {
    const base = three(20000);
    const d = s.setFixed(base, id(base, "Vijay"), 5000, 20000)!;
    expect(s.shares(d, 20000)).toEqual([5000, 10000, 5000]);
    expect(s.shares(d, 23000)).toEqual([6000, 11000, 6000]);
    expect(s.shares(s.setFixed(d, id(d, "Vijay"), null, 23000)!, 23000)).toEqual([7667, 7667, 7666]);
  });

  it("refuses negative fixed amounts", () => {
    const d = three(10000);
    expect(s.setFixed(d, id(d, "Vijay"), -1000, 10000)).toBeNull();
  });

  it("everyone typed with money left -> asks for someone to take the remainder", () => {
    let d = three(20000);
    d = s.setAmountText(d, id(d, "Me"), "70");
    d = s.setAmountText(d, id(d, "Vijay"), "50");
    d = s.setAmountText(d, id(d, "Riyadh"), "50");
    expect(s.problem(d, 20000)).toMatch(/^RM 30\.00 remains unassigned\. Select at least one participant/);
  });

  it("two people: typing both hands the earlier one back to Auto Calculate (You 70 -> Bijoy 30, then Bijoy 40 -> You 60)", () => {
    let d = s.addPerson(s.newDraft(), { id: "b", name: "Bijoy" });
    d = s.setMethod(d, "amounts", 10000);
    d = s.setAmountText(d, id(d, "Me"), "70", 10000);
    expect(s.shares(d, 10000)).toEqual([7000, 3000]);
    d = s.setAmountText(d, id(d, "Bijoy"), "40", 10000);
    expect(s.shares(d, 10000)).toEqual([6000, 4000]);
  });

  it("someone paid for me: my share is the whole total; only my share row is saved", () => {
    let d = s.setPurpose(s.addPerson(s.newDraft(), { id: "b", name: "Bijoy" }), "paidFor");
    d = s.setPayer(d, { id: "b", name: "Bijoy" });
    expect(s.shares(d, 2000)).toEqual([2000, 0]);
    expect(s.shareRows(d, 2000)).toEqual([{ personId: null, isMe: true, nameSnapshot: "Me", amountMinor: 2000, parts: null, enteredMinor: null, sortIndex: 0 }]);
  });

  it("a split that does not match the total is never saved", () => {
    let d = s.setAutoCalculate(s.setMethod(s.addPerson(s.newDraft(), { id: "b", name: "Bijoy" }), "amounts", 10000), false, 10000);
    d = s.setAmountText(d, id(d, "Me"), "60", 10000);
    d = s.setAmountText(d, id(d, "Bijoy"), "20", 10000);
    expect(s.shareRows(d, 10000)).toBeNull();
    expect(s.remainingMinor(d, 10000)).toBe(2000);
  });

  it("loads a saved split exactly (Auto Calculate OFF, no fixed amounts inferred)", () => {
    const d = s.draftFromShares({ paidByMe: true, payerId: null, payerNameSnapshot: null, splitMethod: "amounts" }, [
      { id: "1", personId: null, isMe: true, nameSnapshot: "Me", amountMinor: 6000, parts: null, enteredMinor: 6000, sortIndex: 0 },
      { id: "2", personId: "v", isMe: false, nameSnapshot: "Vijay", amountMinor: 3000, parts: null, enteredMinor: 3000, sortIndex: 1 },
    ], () => undefined)!;
    expect(d.autoCalculate).toBe(false);
    expect(s.shares(d, 9000)).toEqual([6000, 3000]);
    expect(d.participants.every((p) => p.fixedMinor === null)).toBe(true);
  });
});
