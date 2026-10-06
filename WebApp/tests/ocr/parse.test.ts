import { describe, expect, it } from "vitest";
import { knownMerchant, learnedChannel, learnedCategory, suggestCategory, suggestChannel } from "@/lib/ocr/classify";
import { parseReceipt } from "@/lib/ocr/parse";

const tng = (type: string, merchant: string, amount = "12.50") =>
  ["Transaction Details", "Successful", `- RM ${amount}`, "Transaction Type", type, "Merchant", merchant, "Payment Method", "eWallet Balance", "Date/Time", "05/10/2026 13:22", "Transaction No.", "2026100512345678"];

describe("receipt parsing (same evidence rules as iOS)", () => {
  it("Touch 'n Go DuitNow QR at a restaurant", () => {
    const r = parseReceipt(tng("DuitNow QR", "NASI KANDAR PELITA"));
    expect(r).toMatchObject({ amountMinor: 1250, merchant: "NASI KANDAR PELITA", funding: "Touch 'n Go", reference: "2026100512345678" });
    expect(r.channel.value).toBe("DUITNOW_QR");
    expect(r.category.value).toBe("Food");
    expect(new Date(r.date!).getDate()).toBe(5);
  });
  it("Touch 'n Go without channel wording → Unknown (never DuitNow QR or Online)", () => {
    expect(parseReceipt(tng("Payment", "MCDONALD'S BANGSAR")).channel.value).toBe("UNKNOWN");
  });
  it("Maybank card purchase → Card / Maybank", () => {
    const r = parseReceipt(["Maybank", "Card Purchase", "Maybank Visa Debit", "RM 32.90", "Merchant", "UNIQLO MID VALLEY", "Approval Code 123456", "06 Oct 2026"]);
    expect([r.amountMinor, r.funding, r.channel.value, r.category.value]).toEqual([3290, "Maybank", "CARD", "Shopping"]);
  });
  it("balance lines are not the amount", () => {
    expect(parseReceipt(["Payment Successful", "RM 6.00", "Available balance RM 1,234.56"]).amountMinor).toBe(600);
  });
  it("recipient bank is not the funding account", () => {
    expect(parseReceipt(["Maybank", "Transfer Successful", "RM 50.00", "DuitNow Transfer", "Recipient's Name", "ALI BIN ABU", "Recipient's Bank", "CIMB Bank"]).funding).toBe("Maybank");
  });
  it("low-confidence channel words are ignored", () => {
    const r = parseReceipt([{ text: "Maybank", confidence: 0.9 }, { text: "RM 9.00", confidence: 0.9 }, { text: "DuitNow QR", confidence: 0.3 }]);
    expect(r.channel.value).toBe("UNKNOWN");
  });
});

describe("classification", () => {
  it("merchant normalisation: variants match, look-alikes don't", () => {
    expect(["MCD", "MCDONALDS", "7ELEVEN", "LOTUSS MALAYSIA"].map((m) => knownMerchant(m)?.name)).toEqual(["McDonald's", "McDonald's", "7-Eleven", "Lotus's"]);
    expect(["MCDERMOTT LAW", "SHELLY BEAUTY", "DIGITAL STORE", "ATMOS CAFE"].map((m) => knownMerchant(m)?.name ?? null)).toEqual([null, null, null, null]);
  });
  it("whole words only: SMART BUSINESS is not groceries or transport", () => {
    expect(suggestCategory("SMART BUSINESS PROVIDER").value).toBe("Other");
  });
  it("plain Grab needs review", () => {
    expect(suggestCategory("GRAB").needsReview).toBe(true);
  });
  it("Online Payment → Other channel only with wording", () => {
    expect(suggestChannel("Online Payment").value).toBe("OTHER");
  });
  it("learned category: once when evidence is weak, twice beats a known merchant", () => {
    const rule = (hitCount: number) => [{ id: "r", merchantKey: "mcdonald's", category: "Shopping" as const, suggestedType: null, accountId: null, hitCount, createdAt: "", updatedAt: "", deletedAt: null }];
    expect(learnedCategory("MCD BANGSAR", suggestCategory("MCD BANGSAR"), rule(1)).value).toBe("Food");
    expect(learnedCategory("MCD BANGSAR", suggestCategory("MCD BANGSAR"), rule(2)).value).toBe("Shopping");
  });
  it("learned channel only per merchant + funding, only when the receipt is silent", () => {
    const rules = [{ id: "c", merchantKey: "ah seng", fundingKey: "touch 'n go", channel: "DUITNOW_QR" as const, hitCount: 2, createdAt: "", updatedAt: "", deletedAt: null }];
    expect(learnedChannel("Ah Seng", "Touch 'n Go", "UNKNOWN", rules)?.value).toBe("DUITNOW_QR");
    expect(learnedChannel("Ah Seng", "Maybank", "UNKNOWN", rules)).toBeNull();
    expect(learnedChannel("Ah Seng", "Touch 'n Go", "CARD", rules)).toBeNull();
  });
});
