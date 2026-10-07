// @vitest-environment jsdom
// Hybrid Split in the real TransactionForm: toggling on, the three layers, live recalculation, the exact validation
// messages, saving (rule on the expense), reloading a saved Hybrid Split for editing, and "Paid for Someone".
// Run at a phone width and a desktop width (jsdom does no layout; this checks the same flow works at either width).
import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { TransactionForm } from "@/components/transaction-form";
import type { Expense, ExpenseShare, Person } from "@/lib/domain/types";

const state = vi.hoisted(() => ({
  saveExpense: vi.fn<(...args: unknown[]) => Promise<void>>(async () => undefined),
  push: vi.fn(),
  shares: new Map<string, unknown[]>(),
}));

const T = "2026-10-01T10:00:00.000Z";
const RULE = '{"type":"hybrid","version":1,"groups":[{"amountMinor":10000,"members":[1,2]}],"individuals":[{"participant":2,"amountMinor":2000}],"remaining":[0,1,2]}';

vi.mock("next/navigation", () => ({ useRouter: () => ({ push: state.push }) }));
vi.mock("@/components/providers/data-provider", () => {
  const t = "2026-10-01T10:00:00.000Z";
  const people = ["Riad", "Bijoy", "Vijay"].map((name) => ({ id: `p-${name.toLowerCase()}`, name, notes: null, isFrequent: true, isArchived: false, createdAt: t, updatedAt: t, deletedAt: null }));
  const live = { expenses: [], shares: state.shares, movements: [], people, accounts: [], paymentMethods: [], allocations: [] };
  const value = {
    live, dataset: { accounts: [], people, paymentMethods: [], expenses: [], shares: [], movements: [], allocations: [], classificationRules: [], channelRules: [] },
    source: { uploadReceipt: vi.fn(), removeReceipt: vi.fn() },
    saveExpense: (...a: unknown[]) => state.saveExpense(...a), saveRecords: vi.fn(async () => undefined),
  };
  return { useData: () => value };
});

afterEach(cleanup);

const isOn = (el: HTMLElement) => (el as HTMLInputElement).checked;
const box = (label: string) => screen.getByLabelText(label);
const groupCard = (n: number) => box(`Group fixed amount ${n}`);
const check = (container: HTMLElement, legend: string, who: string) =>
  within(within(container).getByRole("group", { name: legend })).getByRole("checkbox", { name: who });
const remainingChecks = () => screen.getByRole("group", { name: "Split remaining between" });
const alertText = () => screen.getByRole("alert").textContent;
const detail = (text: string) => screen.getByText(text, { selector: "p" });
const type = (el: HTMLElement, value: string) => fireEvent.change(el, { target: { value } });
const choosePerson = (n: number, name: string) => {
  const select = box(`Person for individual fixed amount ${n}`) as HTMLSelectElement;
  type(select, (within(select).getByRole("option", { name }) as HTMLOptionElement).value);
};

function startSplit(people = ["Riad", "Bijoy"]) {
  render(<TransactionForm />);
  type(box("Enter amount"), "200");
  type(box("Merchant / Recipient"), "Dinner");
  fireEvent.click(screen.getByRole("switch", { name: /Split Transaction/ }));
  for (const name of people) fireEvent.click(screen.getByRole("button", { name: `+ ${name}` }));
}

describe.each([
  ["phone", 390],
  ["desktop", 1280],
])("Hybrid Split (%s width)", (_label, width) => {
  beforeEach(() => {
    state.saveExpense.mockClear();
    state.push.mockClear();
    state.shares.clear();
    Object.defineProperty(window, "innerWidth", { configurable: true, value: width });
    window.dispatchEvent(new Event("resize"));
  });

  it("builds a group + individual + remaining split live, validates, and saves the rule", async () => {
    startSplit();
    const toggle = screen.getByRole("switch", { name: /Hybrid Split/ });
    expect(screen.getByRole("radiogroup", { name: "Split method" })).toBeTruthy();
    fireEvent.click(toggle);
    expect(isOn(toggle)).toBe(true);
    expect(screen.queryByRole("radiogroup", { name: "Split method" })).toBeNull();
    expect(screen.queryByRole("switch", { name: /Auto Calculate/ })).toBeNull();
    for (const h of [/group fixed amount/i, /individual fixed amounts/i, /remaining amount/i]) expect(screen.getByRole("heading", { name: h })).toBeTruthy();
    expect(screen.getByText("Final calculation")).toBeTruthy();
    expect(screen.getByText("Auto Calculate: ON")).toBeTruthy();
    for (const who of ["You", "Riad", "Bijoy"]) expect(isOn(within(remainingChecks()).getByRole("checkbox", { name: who }))).toBe(true);
    const save = screen.getByRole("button", { name: /Save Expense/ }) as HTMLButtonElement;
    expect(alertText()).toBe("Add a group fixed amount or an individual fixed amount.");
    expect(save.disabled).toBe(true);

    // Layer 1: group fixed amount (a total divided between the group)
    type(within(groupCard(1)).getByLabelText("Amount (total for the group)"), "100");
    expect(alertText()).toBe("Choose who shares group fixed amount 1.");
    fireEvent.click(check(groupCard(1), "Divide this amount between", "Riad"));
    fireEvent.click(check(groupCard(1), "Divide this amount between", "Bijoy"));
    expect(box("Group fixed amount 1 per person").textContent).toBe("Riad RM 50.00Bijoy RM 50.00");
    expect(within(groupCard(1)).getByText("Group allocation").nextSibling?.textContent).toBe("RM 100.00");
    expect(screen.getByTestId("hybrid-remaining").textContent).toBe("RM 100.00");

    // Layer 2: individual fixed amount (one person, not divided)
    fireEvent.click(screen.getByRole("button", { name: "+ Add Individual Fixed Amount" }));
    type(box("Individual fixed amount 1"), "20");
    expect(alertText()).toBe("Choose a person for each individual fixed amount.");
    choosePerson(1, "Bijoy");
    expect(screen.getByText("Individual allocation").nextSibling?.textContent).toBe("RM 20.00");
    expect(screen.getByTestId("hybrid-remaining").textContent).toBe("RM 80.00");

    // Final calculation: one row per person with how it is made up
    expect(detail("RM 26.67 remaining")).toBeTruthy();
    expect(detail("RM 50.00 group + RM 26.67 remaining")).toBeTruthy();
    expect(detail("RM 50.00 group + RM 20.00 individual + RM 26.66 remaining")).toBeTruthy();
    expect(screen.getByText("Total allocated").nextSibling?.textContent).toBe("RM 200.00");
    expect(screen.getByText("Remaining").nextSibling?.textContent).toBe("RM 0.00");
    expect(screen.queryByRole("alert")).toBeNull();
    expect(save.disabled).toBe(false);

    // Live changes and validation
    type(box("Individual fixed amount 1"), "200");
    expect(alertText()).toBe("Fixed allocations exceed the transaction total by RM 100.00.");
    expect(screen.getByText("Remaining").nextSibling?.textContent).toBe("−RM 100.00");
    expect(save.disabled).toBe(true);
    type(box("Individual fixed amount 1"), "20");
    fireEvent.click(screen.getByRole("button", { name: "+ Add Individual Fixed Amount" }));
    choosePerson(2, "Bijoy");
    type(box("Individual fixed amount 2"), "5");
    expect(alertText()).toBe("Bijoy already has an individual fixed amount.");
    fireEvent.click(screen.getByRole("button", { name: "Remove individual fixed amount 2" }));
    fireEvent.click(screen.getByRole("button", { name: "+ Add Another Group" }));
    type(within(groupCard(2)).getByLabelText("Amount (total for the group)"), "10");
    expect(alertText()).toBe("Choose who shares group fixed amount 2.");
    fireEvent.click(screen.getByRole("button", { name: "Remove group 2" }));
    for (const who of ["You", "Riad", "Bijoy"]) fireEvent.click(within(remainingChecks()).getByRole("checkbox", { name: who }));
    expect(alertText()).toBe("RM 80.00 is left after the fixed allocations. Choose who shares the remaining amount.");
    for (const who of ["You", "Riad", "Bijoy"]) fireEvent.click(within(remainingChecks()).getByRole("checkbox", { name: who }));
    // A person added while on joins the remaining group only; removing takes them out again.
    fireEvent.click(screen.getByRole("button", { name: "+ Vijay" }));
    expect(isOn(within(remainingChecks()).getByRole("checkbox", { name: "Vijay" }))).toBe(true);
    expect(isOn(check(groupCard(1), "Divide this amount between", "Vijay"))).toBe(false);
    expect(detail("RM 50.00 group + RM 20.00 individual + RM 20.00 remaining")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Remove Vijay" }));
    type(box("Enter amount"), "230");
    expect(detail("RM 50.00 group + RM 20.00 individual + RM 36.66 remaining")).toBeTruthy();
    type(box("Enter amount"), "200");

    fireEvent.click(screen.getByRole("button", { name: /Save Expense · RM 200.00/ }));
    await vi.waitFor(() => expect(state.saveExpense).toHaveBeenCalledTimes(1));
    const [record, shares] = state.saveExpense.mock.calls[0] as unknown as [Expense, ExpenseShare[]];
    expect(record).toMatchObject({ splitMethod: "amounts", splitRule: RULE });
    expect(shares.map((s) => [s.nameSnapshot, s.amountMinor, s.enteredMinor, s.sortIndex])).toEqual([["Me", 2667, 2667, 0], ["Riad", 7667, 7667, 1], ["Bijoy", 9666, 9666, 2]]);
    // Turning it off goes back to the method used before.
    fireEvent.click(screen.getByRole("switch", { name: /Hybrid Split/ }));
    expect(screen.getByRole("radio", { name: "Split Equally" }).getAttribute("aria-checked")).toBe("true");
  });

  it('"Paid for Someone" hides and turns off Hybrid Split', () => {
    startSplit(["Riad"]);
    fireEvent.click(screen.getByRole("switch", { name: /Hybrid Split/ }));
    fireEvent.click(screen.getByRole("radio", { name: "Paid for Someone" }));
    expect(screen.queryByRole("switch", { name: /Hybrid Split/ })).toBeNull();
    fireEvent.click(screen.getByRole("radio", { name: "Shared Expense" }));
    expect(isOn(screen.getByRole("switch", { name: /Hybrid Split/ }))).toBe(false);
  });

  it("editing a saved Hybrid Split restores every layer and recalculates for a new amount", async () => {
    const expense: Expense = {
      id: "e1", amountMinor: 20000, currency: "RM", merchant: "Dinner", category: "Food", paymentChannel: "UNKNOWN", fundingAccount: "Unknown",
      fundingInstrument: null, accountId: null, paymentSource: null, date: T, notes: null, transactionReference: null, sourceType: "manual",
      paidByMe: true, payerId: null, payerNameSnapshot: null, splitMethod: "amounts", splitRule: RULE, receiptPath: null, isSampleData: false,
      createdAt: T, updatedAt: T, deletedAt: null,
    };
    const row = (id: string, p: Pick<Person, "id" | "name"> | null, amount: number, sortIndex: number): ExpenseShare => ({
      id, expenseId: "e1", personId: p?.id ?? null, isMe: !p, nameSnapshot: p?.name ?? "Me", amountMinor: amount, parts: null, enteredMinor: amount,
      sortIndex, createdAt: T, updatedAt: T, deletedAt: null,
    });
    state.shares.set("e1", [row("s0", null, 2667, 0), row("s1", { id: "p-riad", name: "Riad" }, 7667, 1), row("s2", { id: "p-bijoy", name: "Bijoy" }, 9666, 2)]);
    render(<TransactionForm expense={expense} />);
    expect(isOn(screen.getByRole("switch", { name: /Hybrid Split/ }))).toBe(true);
    expect((within(groupCard(1)).getByLabelText("Amount (total for the group)") as HTMLInputElement).value).toBe("100.00");
    expect(isOn(check(groupCard(1), "Divide this amount between", "Riad"))).toBe(true);
    expect(isOn(check(groupCard(1), "Divide this amount between", "You"))).toBe(false);
    expect((box("Individual fixed amount 1") as HTMLInputElement).value).toBe("20.00");
    expect((box("Person for individual fixed amount 1") as HTMLSelectElement).selectedOptions[0].textContent).toBe("Bijoy");
    type(box("Enter amount"), "300");
    expect(detail("RM 50.00 group + RM 20.00 individual + RM 60.00 remaining")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Save Changes" }));
    await vi.waitFor(() => expect(state.saveExpense).toHaveBeenCalledTimes(1));
    const [record, shares] = state.saveExpense.mock.calls[0] as unknown as [Expense, ExpenseShare[]];
    expect(record).toMatchObject({ id: "e1", amountMinor: 30000, splitMethod: "amounts", splitRule: RULE });
    expect(shares.map((s) => [s.id, s.amountMinor])).toEqual([["s0", 6000], ["s1", 11000], ["s2", 13000]]);
  });
});
