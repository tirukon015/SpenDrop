// Natural dates resolve to exact days in the USER's time zone (§28, §110, §302).
import { describe, expect, it } from "vitest";
import { extractAmount, extractPeriod, plan } from "@/lib/ai/planner";
import { localDateOf, previousComparable, presetSpan, spanInstants } from "@/lib/ai/time";

const today = "2026-10-07"; // Wednesday
const span = (q: string) => extractPeriod(q, today)?.span;

describe("natural dates (today = Wed 7 Oct 2026)", () => {
  it.each([
    ["today", { from: "2026-10-07", to: "2026-10-07" }],
    ["yesterday", { from: "2026-10-06", to: "2026-10-06" }],
    ["last Saturday", { from: "2026-10-03", to: "2026-10-03" }],
    ["on Wednesday", { from: "2026-10-07", to: "2026-10-07" }],
    ["last Wednesday", { from: "2026-09-30", to: "2026-09-30" }],
    ["this week", { from: "2026-10-05", to: "2026-10-11" }],
    ["last week", { from: "2026-09-28", to: "2026-10-04" }],
    ["this month", { from: "2026-10-01", to: "2026-10-31" }],
    ["last month", { from: "2026-09-01", to: "2026-09-30" }],
    ["October 7", { from: "2026-10-07", to: "2026-10-07" }],
    ["7th of October", { from: "2026-10-07", to: "2026-10-07" }],
    ["December 25", { from: "2025-12-25", to: "2025-12-25" }], // a future date without a year means last year
    ["in September", { from: "2026-09-01", to: "2026-09-30" }],
    ["last 3 days", { from: "2026-10-05", to: "2026-10-07" }],
    ["5/10", { from: "2026-10-05", to: "2026-10-05" }], // day/month, as in Malaysia
    ["minggu ini", { from: "2026-10-05", to: "2026-10-11" }],
  ])("%s", (q, expected) => expect(span(q)).toEqual(expected));

  it("“may” is only a month when it clearly is one", () => {
    expect(span("may I see my spending")).toBeUndefined();
    expect(span("in May")).toEqual({ from: "2026-05-01", to: "2026-05-31" });
  });

  it("an amount is never mistaken for a date and vice versa", () => {
    expect(extractAmount("Where did my RM15 go on October 7?")).toMatchObject({ target: 15, min: 13.5, max: 16.5 });
    expect(extractAmount("what happened on October 7")).toBeNull();
    expect(extractAmount("around RM50")).toMatchObject({ min: 40, max: 60, approximate: true });
    expect(extractAmount("between RM20 and RM30")).toMatchObject({ min: 20, max: 30, target: null });
    expect(extractAmount("over RM100")).toMatchObject({ min: 100 });
  });
});

describe("time zones and day boundaries", () => {
  it("a payment at 00:30 Malaysia time belongs to that Malaysian day, not the UTC day before", () => {
    expect(localDateOf("2026-10-06T16:30:00Z", "Asia/Kuala_Lumpur")).toBe("2026-10-07");
    expect(localDateOf("2026-10-06T16:30:00Z", "Europe/London")).toBe("2026-10-06");
  });

  it("a day span becomes exact instants in the user's zone", () => {
    const { start, end } = spanInstants({ from: "2026-10-07", to: "2026-10-07" }, "Asia/Kuala_Lumpur");
    expect(start.toISOString()).toBe("2026-10-06T16:00:00.000Z");
    expect(end.toISOString()).toBe("2026-10-07T16:00:00.000Z");
  });

  it("handles daylight-saving changes (London, 25 Oct 2026 is 25 hours long)", () => {
    const { start, end } = spanInstants({ from: "2026-10-25", to: "2026-10-25" }, "Europe/London");
    expect((end.getTime() - start.getTime()) / 3_600_000).toBe(25);
    expect(start.toISOString()).toBe("2026-10-24T23:00:00.000Z");
  });

  it("the plan's “today” follows the user's zone", () => {
    const p = plan({ message: "How much did I spend today?", today: "2026-10-08", vocabulary: { merchants: [], fundingAccounts: [], currencies: [], earliestDate: null, expenseCount: 1 }, focus: null });
    expect(p.kind === "tools" && p.steps[0].args.period).toEqual({ from: "2026-10-08", to: "2026-10-08" });
  });
});

describe("fair comparisons", () => {
  it("this month so far vs the same days of last month", () => {
    expect(previousComparable(presetSpan("this_month", today)!, today)).toEqual({ from: "2026-09-01", to: "2026-09-07" });
  });
  it("a finished month vs the whole previous month", () => {
    expect(previousComparable(presetSpan("last_month", today)!, today)).toEqual({ from: "2026-08-01", to: "2026-08-31" });
  });
  it("this week so far vs the same weekdays last week", () => {
    expect(previousComparable(presetSpan("this_week", today)!, today)).toEqual({ from: "2026-09-28", to: "2026-09-30" });
  });
  it("31 March → compared with 1–28 February, not a non-existent 31 February", () => {
    expect(previousComparable(presetSpan("this_month", "2026-03-31")!, "2026-03-31")).toEqual({ from: "2026-02-01", to: "2026-02-28" });
  });
});
