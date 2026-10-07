# Business rules

Every rule below is implemented identically on iOS and Web. The JSON files are executable test vectors.

## Money (`money-test-vectors.json`)
- All amounts are **integer minor units** (sen). RM 10.50 = 1050. Never floating point for calculations.
- Typed text → sen: strip `RM`/`MYR`/commas, round half up (`"33.335"` → 3334). Invalid → rejected, never guessed.
- Display: `RM 1,234.50`; negative `-RM 5.00`. Different currencies are never added together.

## Funding account vs payment channel
- **Funding account** = where the money came from (Maybank, CIMB, RHB, Wise, Touch 'n Go, Cash).
- **Payment channel** = how it was paid (Apple Pay, DuitNow QR, Touch 'n Go QR, Card, Bank Transfer, Cash, Other, Unknown).
- Apple Pay, QR and Bank Transfer are never accounts. The SpenDrop login is neither.
- `UNKNOWN` is valid and explicit. A channel is set only from evidence on the receipt (or a learned rule confirmed
  twice for the same merchant **and** funding account) — never from the bank or wallet name alone.

## Splitting (`split-test-vectors.json`)
- Participants: Me (always, first) + people. Methods: **equal**, **parts** (1–99), **amounts** (custom).
- Equal / parts: largest-remainder rounding; leftover sen go to **Me first when I paid**, then list order. The
  shares always add up exactly to the total.
- **Auto Calculate** (amounts) is ON for every new transaction and applies to that transaction only:
  typed amounts are kept exactly; what's left (total − typed − fixed) is shared equally by everyone not typed for —
  Me included; each person with a **fixed amount** gets fixed + their equal part. Typing the last untyped person
  hands the earliest-typed person back to the calculation. Clearing a box hands that person back.
- Auto Calculate **OFF**: amounts shown are frozen; nothing changes by itself; "RM X remains unassigned." until it adds up.
- Errors (exact wording shared): "Fixed amounts exceed the expense total by RM X.", "Shares exceed the total by RM X.",
  "RM X remains unassigned.", "Add at least one other person.".
- **Hybrid Split** (`split-hybrid.md`, `split-hybrid-vectors.json`): group fixed amounts (a total divided equally
  between the group), individual fixed amounts (one person, not divided), then the remaining amount split equally
  between a chosen group. A person's amount is the sum of every layer they're in. Same rounding as Split Equally.
- **Paid for someone**: I paid for the listed people (my share 0) or someone paid entirely for me (my share = total).
- A split that doesn't add up is never saved; the transaction amount is never changed to make it fit.

## Balances and settlements
- Person balance: expenses I paid add others' shares (they owe me); an expense a person paid adds my share as owed
  to them; loans/repayments by sign (`money-movement-kinds.json` → `personBalanceSign`). Positive = they owe me.
- Debts are per transaction; settlements record **allocations** (payment / assign / offset) and never modify the
  original expense or loan. Mark as Paid = one payment for what's left. Payments not linked = **credit**.
- **Settle All**: 1) apply earlier unlinked payments oldest first, 2) offset opposite debts (no money moves),
  3) one payment for the rest. One action = one Undo.
- Own transfers never count as income or spending. Spending = full amount if I paid, my share otherwise.
