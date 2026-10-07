# Hybrid Split

A mode of the existing Split Transaction (purpose **Shared** only). Three allocation layers, applied together:

1. **Group Fixed Amount** — a TOTAL amount divided equally between the people selected for that group
   (RM 100 between Riad and Bijoy = RM 50 each, never RM 100 each). Several groups are allowed.
2. **Individual Fixed Amount** — an amount for one person only, never divided. Several are allowed (one per person).
3. **Remaining Amount** — `total − all group amounts − all individual amounts`, split equally between the people
   selected for the remaining amount.

A person may be in any combination of layers; their final amount is the sum of what each layer gives them. Me is a
participant like anyone else (any layer, or none → RM 0.00). One row per participant. Integer sen only.
Executable cases: `split-hybrid-vectors.json`.

## Calculation
- Every equal division (each group, and the remaining amount) uses the existing **Split Equally** rule: floor, then
  leftover sen one at a time; ties → Me first when I paid, then participant order. So every group adds up exactly to
  its amount and the remaining shares add up exactly to the remaining amount; the final amounts add up exactly to the
  total.
- `groupAllocation = Σ group amounts`, `individualAllocation = Σ individual amounts`,
  `fixedAllocation = groupAllocation + individualAllocation`, `remaining = total − fixedAllocation`.
- If `remaining = 0` nothing is divided (the remaining group may be empty).
- Live: recalculated on every change (total, any amount, any member, any person); there is no Calculate button.

## Rows the user hasn't filled in
- A group with **no amount and no members** is ignored (it's the empty starter group).
- An individual row with **no person and no amount** is ignored.
- Anything partly filled is checked (below).

## Problems (first one found, in this order; exact wording shared)
| # | Condition | Message |
|---|---|---|
| 1 | total ≤ 0 | `Enter the expense amount first.` |
| 2 | no other person in the split | `Add at least one other person.` |
| 3 | group N: amount empty / not a number / ≤ 0 | `Enter the amount for group fixed amount N.` |
| 4 | group N: no members | `Choose who shares group fixed amount N.` |
| 5 | individual row without a person | `Choose a person for each individual fixed amount.` |
| 6 | individual for Name: amount empty / not a number / ≤ 0 | `Enter the individual fixed amount for Name.` |
| 7 | a second individual row for the same person | `Name already has an individual fixed amount.` |
| 8 | no group and no individual amount left after ignoring empty rows | `Add a group fixed amount or an individual fixed amount.` |
| 9 | fixedAllocation > total | `Fixed allocations exceed the transaction total by RM X.` (X = fixedAllocation − total) |
| 10 | remaining > 0 and nobody selected for it | `RM X is left after the fixed allocations. Choose who shares the remaining amount.` |
| 11 | a person (not Me) in no layer | `Name isn't in any part of the split. Add them to an allocation or remove them.` |

Checks 3–4 run **group by group** (group 1: amount, then members; then group 2 …) and checks 5–7 **row by row**, so the
first broken group or row is the one named. Groups are numbered from 1 in the order shown. "Name" is the person's name ("You" is never named — Me can't be in
problems 6, 7 or 11 except as "You": use `You` for Me in 6 and 7). A split with a problem is never saved.

## Behaviour
- Turning **Hybrid Split** on: one empty group, no individual amounts, remaining = everyone in the split (Me
  included). The method picker (Split Equally / Parts / Custom Amount) and Auto Calculate switch aren't used while it
  is on. Turning it off returns to the method used before.
- Adding a person while on: they join the remaining group only. Removing a person removes them from every group,
  deletes their individual row(s) and removes them from the remaining group.
- "Paid for someone" has no Hybrid Split (choosing it turns Hybrid Split off).
- Labels: section "HYBRID SPLIT"; "GROUP FIXED AMOUNT" (field "Amount (total for the group)", "Divide this amount
  between", per-person preview "Riad RM 50.00", "Group allocation RM 100.00"), "+ Add Another Group";
  "INDIVIDUAL FIXED AMOUNTS" (rows "Person ▾  RM amount  Remove", "+ Add Individual Fixed Amount",
  "Individual allocation RM 20.00"); "REMAINING AMOUNT" (amount, "Split remaining between", "Auto Calculate: ON");
  "FINAL CALCULATION" (one row per person, with how it's made up, e.g. "RM 50.00 group + RM 20.00 individual +
  RM 26.66 remaining"); "Total allocated", "Remaining".

## Persistence (backwards compatible)
- Shares are saved exactly like a Custom Amount split: `expense.split_method = "amounts"`, each row `amount_minor` =
  `entered_minor` = final amount, `sort_index` = participant position (Me = 0, then people in order). Older app
  versions, analytics, balances and PayBook only see normal amounts.
- The rule is one optional text field on the **expense**: `split_rule` (cloud) / `splitRule` (app models and backup
  JSON, a string). null = a normal split. Canonical JSON (keys in this order, no spaces):
  `{"type":"hybrid","version":1,"groups":[{"amountMinor":10000,"members":[1,2]}],"individuals":[{"participant":2,"amountMinor":2000}],"remaining":[0,1,2]}`
  Numbers in `members` / `participant` / `remaining` are participant positions (= the shares' `sort_index`). Ignored
  empty rows are not saved.
- Reload: when `splitRule` parses as `type == "hybrid"` and every position matches a live share, the draft reopens in
  Hybrid Split with the amounts and groups restored; otherwise (unknown type, bad JSON, missing shares) it opens as the
  normal Custom Amount split it also is. Old expenses have no `splitRule` and load exactly as before.
- Amount of a saved Hybrid Split changes: recalculated with the same rule; if it no longer works the shares are left
  as they were and reported as not matching the amount.
- Backup JSON (`ExpenseDTO`): optional `splitRule` string, omitted when null; old backups load unchanged.
- Cloud: migration `20261008000000_hybrid_split.sql` adds `expenses.split_rule text` (≤ 4000 chars) and makes
  `save_expense_with_shares` store it. Until it is applied the RPC ignores the key and the expense still saves (as a
  plain Custom Amount split).
