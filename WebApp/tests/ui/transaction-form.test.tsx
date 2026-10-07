// @vitest-environment jsdom
// The Add page's TransactionForm keeps its behaviour after the draft-state refactor: it saves and navigates.
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { TransactionForm } from "@/components/transaction-form";

const push = vi.fn();
const saveExpense = vi.fn(async () => undefined);
vi.mock("next/navigation", () => ({ useRouter: () => ({ push }) }));
vi.mock("@/components/providers/data-provider", () => {
  const live = { expenses: [], shares: new Map(), movements: [], people: [], accounts: [], paymentMethods: [], allocations: [] };
  const value = {
    live, dataset: { accounts: [], people: [], paymentMethods: [], expenses: [], shares: [], movements: [], allocations: [], classificationRules: [], channelRules: [] },
    source: { uploadReceipt: vi.fn(), removeReceipt: vi.fn() }, saveExpense: (...a: unknown[]) => saveExpense(...(a as [])), saveRecords: vi.fn(async () => undefined),
  };
  return { useData: () => value };
});

afterEach(cleanup);

describe("TransactionForm (standalone)", () => {
  it("saves a new expense with the typed values and opens it", async () => {
    render(<TransactionForm />);
    fireEvent.change(screen.getByLabelText("Enter amount"), { target: { value: "12.50" } });
    fireEvent.change(screen.getByLabelText("Merchant / Recipient"), { target: { value: "Tealive" } });
    fireEvent.click(screen.getByRole("button", { name: /Save Expense · RM 12.50/ }));
    await waitFor(() => expect(saveExpense).toHaveBeenCalledTimes(1));
    const [record, shares] = saveExpense.mock.calls[0] as unknown as [{ id: string; merchant: string; amountMinor: number; sourceType: string }, unknown[]];
    expect(record).toMatchObject({ merchant: "Tealive", amountMinor: 1250, sourceType: "manual" });
    expect(shares).toEqual([]);
    await waitFor(() => expect(push).toHaveBeenCalledWith(`/transactions/${record.id}`));
  });
});
