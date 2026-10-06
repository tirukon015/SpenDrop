# Validation

| Field | Rule |
|---|---|
| Amount | integer sen, > 0, ≤ 1,000,000,000.00 (database CHECK); typed text parsed per `BusinessRules/money-test-vectors.json` |
| Share amount | integer sen, ≥ 0; shares of an expense add up exactly to its amount |
| Parts | whole number 1–99 |
| Fixed amount | ≥ 0; fixed amounts together ≤ the total |
| Category / channel / kind / account type | one of `Constants/*.json` (database CHECK) |
| Movement direction | must match the kind (`income` → `in`, `loanGiven` → `out`, `ownTransfer` → `internal`) |
| Own transfer | two different accounts |
| Loan / repayment | requires a person |
| Merchant | ≤ 200 chars; empty → "Unknown" |
| Names (person, account) | 1–80 chars after trimming |
| Notes | ≤ 4,000 chars (expenses, movements), ≤ 2,000 (people) |
| Reference | ≤ 120 chars |
| Dates | stored as UTC timestamps; ranges use the device's local days, weeks Monday–Sunday |
