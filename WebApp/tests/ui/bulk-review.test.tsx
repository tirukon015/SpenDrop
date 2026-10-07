// @vitest-environment jsdom
// Bulk Import review queue: collapsed cards, expanding into the full transaction editor, and the "Add N" count.
import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { useState } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { BulkReview, type BulkShot } from "@/components/bulk-import";
import { draftsFromScreenshot, type BulkDraft } from "@/lib/bulk-import";
import type { OcrLine } from "@/lib/ocr/parse";

vi.mock("next/navigation", () => ({ useRouter: () => ({ push: vi.fn() }) }));
vi.mock("@/components/providers/data-provider", () => {
  const live = { expenses: [], shares: new Map(), movements: [], people: [], accounts: [], paymentMethods: [], allocations: [] };
  const value = { live, dataset: { accounts: [], people: [], paymentMethods: [], expenses: [], shares: [], movements: [], allocations: [], classificationRules: [], channelRules: [] },
    source: null, saveExpense: vi.fn(), saveRecords: vi.fn() };
  return { useData: () => value };
});

afterEach(cleanup);

const lines = (t: string[]): OcrLine[] => t.map((text) => ({ text, confidence: 0.95 }));
const taken = new Date(2026, 9, 7, 9, 0);
const shots: BulkShot[] = [1, 2, 3].map((n) => ({ n, blob: null, url: null, takenAt: taken, state: "done", progress: 1, removed: false }));
const history = ["Transaction History", "7 Oct — Grab — RM10.50", "7 Oct — McDonald's — RM12.90", "7 Oct — Starbucks — RM15.00"];

function Harness({ initial, onAdd }: { initial: BulkDraft[]; onAdd: (d: BulkDraft[]) => void }) {
  const [drafts, setDrafts] = useState(initial);
  return <BulkReview shots={shots} drafts={drafts} onDraftsChange={setDrafts} onRemoveShot={() => undefined} onAdd={onAdd} />;
}

describe("BulkReview", () => {
  const setup = () => {
    const first = draftsFromScreenshot(lines(history), 1, null, "2026-10-07", taken);
    const again = draftsFromScreenshot(lines(history.slice(0, 2)).concat(lines(["7 Oct — Tealive — RM8.00"])), 2, null, "2026-10-07", taken);
    const onAdd = vi.fn();
    render(<Harness initial={[...first, ...again]} onAdd={onAdd} />);
    return { onAdd };
  };

  it("shows a summary, collapsed cards and an unable-to-detect row", () => {
    setup();
    expect(screen.getByTestId("bulk-summary").textContent).toBe("3 screenshots · 5 detected · 4 ready · 0 need review · 1 possible duplicate");
    const cards = screen.getAllByRole("button", { expanded: false });
    expect(cards).toHaveLength(5);
    expect(screen.queryByLabelText("Merchant / Recipient")).toBeNull();
    expect(screen.getAllByText("Possible Duplicate")).toHaveLength(1);
    expect(screen.getByText("Unable to detect transaction · Screenshot 3")).toBeTruthy();
    expect(screen.getByRole("button", { name: "Add 4 Transactions" })).toBeTruthy();
  });

  it("expanding a card shows the complete transaction editor; edits update the draft", () => {
    setup();
    fireEvent.click(screen.getAllByRole("button", { expanded: false })[0]);
    const merchant = screen.getByLabelText("Merchant / Recipient") as HTMLInputElement;
    expect(merchant.value).toBe("Grab");
    expect(screen.getByLabelText("Funding account (where money came from)")).toBeTruthy();
    expect(screen.getByLabelText("Payment channel (how payment was made)")).toBeTruthy();
    expect((screen.getByLabelText("Date") as HTMLInputElement).value).toBe("2026-10-07");
    expect(screen.getByRole("switch", { name: /Split Transaction/ })).toBeTruthy();
    expect(screen.queryByRole("button", { name: /Save Expense/ })).toBeNull(); // draft mode: nothing saved from the card
    fireEvent.change(merchant, { target: { value: "Grab Food" } });
    expect(screen.getAllByText("Grab Food").length).toBeGreaterThan(0);
  });

  it("Add Anyway includes a duplicate, Remove excludes a card, and Add N passes exactly those drafts", () => {
    const { onAdd } = setup();
    const duplicateCard = screen.getByText("Possible Duplicate").closest("button")!;
    fireEvent.click(duplicateCard);
    fireEvent.click(screen.getByRole("button", { name: "Add Anyway" }));
    expect(screen.getByRole("button", { name: "Add 5 Transactions" })).toBeTruthy();
    fireEvent.click(screen.getAllByRole("button", { name: "Remove" })[0]); // the open card's (unable rows come after the cards)
    expect(screen.getByRole("button", { name: "Add 4 Transactions" })).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Add 4 Transactions" }));
    const added = onAdd.mock.calls[0][0] as BulkDraft[];
    expect(added.map((b) => b.draft.merchant)).toEqual(["Grab", "McDonald's", "Starbucks", "Tealive"]);
    const list = screen.getByRole("list", { name: "Detected transactions" });
    expect(within(list).queryByText("Possible Duplicate")).toBeNull();
  });

  it("Enter Manually turns an unreadable screenshot into an editable draft", () => {
    setup();
    fireEvent.click(screen.getByRole("button", { name: "Enter Manually" }));
    expect(screen.queryByText("Unable to detect transaction · Screenshot 3")).toBeNull();
    expect((screen.getByLabelText("Merchant / Recipient") as HTMLInputElement).value).toBe("");
  });
});
