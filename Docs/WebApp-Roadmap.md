# Web App roadmap

## Done (this release)
Sign-in (Google/email), Home, Transactions (search/filter/sort, phone list + desktop table), Add/Edit/Delete for
expenses and money in/out/transfers, inline splitting (equal/parts/custom, Auto Calculate, fixed amounts,
remaining validation, paid for someone), PayBook (balances, filters, debts, Mark as Paid, payments, credit, Settle
All, Undo, payment details), Breakdown (spending + cash flow), funding accounts, receipts with in-browser OCR,
sharing, import from iPhone backups, appearance, PWA, responsive layouts, accessibility checks, demo mode for
development. 81 unit tests + 44 end-to-end checks across four screen sizes.

## Next
1. **Apply the cloud-records migration in production** (one SQL run — Docs/WebApp-Setup.md) and allow the Web
   callback URLs in Supabase Auth. Until then the deployed site can sign in but cannot load records.
2. **iOS sync** (Docs/Sync-Architecture.md → "Next: iOS sync").
3. Offline writes on Web (IndexedDB outbox replayed on reconnect, same ids → idempotent).
4. Web Share Target (share a screenshot from Android/desktop straight into Add) and PDF receipts (pdf.js, lazy).
5. Measure Web OCR accuracy on real anonymised receipts; consider training data for Malay words.
6. Supabase Realtime for instant cross-device refresh (today: refresh on focus/reconnect/every 2 minutes).
7. Persist fixed-amount configuration (both platforms).
8. Android client using the same Common contracts and tables.

## Known gaps
- Changes made on the Web don't reach the iPhone yet (iOS sync not built).
- iOS screenshots and PayBook photos are not in the cloud.
- The Home/Breakdown figures count RM only (other currencies are never mixed in).
- Very large data sets (tens of thousands of records) are cached in the browser in full; fine for personal use,
  would need server-side aggregation at a much larger scale.
