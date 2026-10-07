# Bulk Screenshot Import — shared rules (iOS, Android, Web)

Bulk Import only automates the first step of adding transactions. Every screenshot becomes one or more **normal
transaction drafts**, edited with the platform's existing transaction editor (same fields, split, validation) and
saved through the existing save path as **separate** records. There is no bulk record type.

## 1. One screenshot → one or several transactions

Each screenshot's OCR lines are classified, using only text:

- **Row** = a line that contains, at once:
  1. exactly one money amount: `RM 10.50`, `RM10.50`, `-RM 10.50`, `+RM 3.00`, `MYR 12.90`, or a bare
     `12.90` / `-12.90` with exactly two decimals (thousand separators allowed);
  2. a date: `7 Oct`, `7 Oct 2026`, `07 Oct 2026`, `07/10/2026`, `7/10/26`, `2026-10-07` (day first);
  3. a description: at least 2 letters left after removing the amount, the date, times (`8:42 PM`, `20:42`)
     and stand-alone separators (`—`, `–`, `-`, `|`, `·`, `•`, `:` with spaces around them or at the start/end;
     a hyphen inside a word such as `7-Eleven` is kept).
- **List** when there are **≥ 2 rows**. Exception: exactly 2 rows **and** the text has a single-receipt marker
  (`payment successful`, `transaction successful`, `successful`, `receipt`, `total`, `ref no`, `reference`)
  → treated as a single receipt.
- Otherwise **single**: the platform's existing receipt parser handles the whole screenshot.

For a list, every row becomes one draft:

- `amountMinor` = the amount in sen (always positive);
- `direction` = `"in"` when the amount has a leading `+`, otherwise `"out"`;
- `merchant` = the description text, whitespace collapsed;
- `date` = the row's date. A date without a year takes the import date's year, or the previous year if that
  would be later than the import date. The time of day is the row's time if present, else 12:00.

Nothing else is guessed for list rows (no funding account, channel or category evidence beyond the platform's
normal merchant → category suggestion).

## 2. Duplicates

Every draft is checked with the platform's **existing** duplicate detector against:

1. the saved transactions, then
2. the drafts that come **before it in the same batch** (the same payment screenshotted twice).

The existing rules apply unchanged: strong = same reference (≥ 4 chars) and same amount within ±48 h; weak = same
amount and merchant within 15 min with no conflicting channel/funding. Manual entries are never checked.

Duplicate actions are the existing ones: **Add Anyway**, **Merge with Existing** (strong match with a saved
transaction only), **Skip**. A possible duplicate starts as **Skip**, so nothing is duplicated unless the user
chooses to add it.

## 3. Status of each draft

- **Possible duplicate**: a match was found (until the user picks Add Anyway / Merge).
- **Needs review**: the draft can't be saved yet (no amount), or the parser found no merchant, or confidence is
  low, or the screenshot looks failed / balance-only.
- **Ready**: everything else.
- A screenshot that produced **no** draft is listed as **Unable to detect a transaction**, never dropped silently.
  The user can review the image, enter it manually, or remove it.

"Add N Transactions" counts the drafts that will actually be saved: not removed, not skipped, and valid.

## 4. Privacy

Screenshots stay on the device (Web: in the browser) until saved; each saved draft keeps **its own** screenshot as
its receipt where the platform supports receipts. Temporary copies are deleted when the session ends. No OCR text,
amounts or merchants are logged.
