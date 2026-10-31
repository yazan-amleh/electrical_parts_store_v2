# Phase 4 — paginated, read-only financial reconciliation (2026-10-23)

## Approval boundary

Repo `yazan-amleh/electrical_parts_store_v2`, branch `audit/systematic-v1-parity-20261023`, draft PR #1. The changes are **code + Firebase Emulator tests only**. No actual V2 customer ledger has been audited in Production, no Firebase deployment, no V1 changes, no financial writes, no migration, and no balance rewriting.

## Traced read-only audit

Authenticated `auditAccountingIntegrity` accepts a store ID and checks membership role (owner/admin/accountant), then scans:
- chart of accounts and stored account balance projections
- posted journal headers and **directly nested** `journal_entries/{entryId}/lines`
- parties, party ledger and stored party balance projections
- products and inventory movements

All reconciliation data is read-only; results are returned to `AccountingAuditPage` in Flutter.

## Fixes delivered

1. **Explicit pagination** — `readAuditPages` orders by Firestore document ID and follows `startAfter(lastSnapshot)` until exhaustion. Tests cover short/full final pages, a document beyond the cap, and **4,101 records** (previous implementation stopped at 4,000). Source query limit is **10,000 documents per collection** and **30,000 documents overall** for this callable. The page size is 200; any query that exceeds the permitted bound returns `status: incomplete`, `complete: false`, a hard issue, and never a healthy result. This is bounded pagination, **not** resumable unbounded processing.
2. **No invoice-line mixing** — retired the audit's general `collectionGroup('lines').where('storeId', ...)` as its primary source. The server reads each journal's own `lines` subcollection with bounded concurrency (8 journal reads in parallel). It includes journal lines with malformed or missing embedded `storeId`, so they become reported errors rather than being silently omitted. The checked journal-line count includes those invalid rows.
3. **Safety of financial math** — rejects bad integer representations, fractional values, negative debit/credit where forbidden, missing fields, numeric overflows, wrong tenants/accounts, mismatched GL and party projections, and inconsistent party currencies and net balances.
4. **Inventory vs GL** — sums product inventory values by currency and compares them to net inventory-control accounts, on top of comparing product quantity/value to inventory movements. Products with stock but no recorded opening/movement evidence produce `INVENTORY_OPENING_SOURCE_UNVERIFIED` (never auto-correct them). Cross-tenant products and movements are flagged.
5. **Complete issue counts** — the client only displays 200 detailed issues, but the server tracks total issues/errors beyond that, returns `issuesTruncated: true`, and never marks a later undisplayed error healthy. Flutter honors server counts and shows that only a subset of details is visible.
6. **Audit honesty** — results always say `consistency: non_atomic`. The UI explicitly warns that separate Firestore scans are **not a consistent point-in-time accounting snapshot**, even if no differences were detected.

## Files changed

- `functions/accounting/audit_integrity.js`
- `functions/index.js`
- `functions/audit_integrity.test.js`
- `functions/accounting_audit_integrity.test.js`
- `lib/features/accounting_audit/domain/entities/accounting_audit_report.dart`
- `lib/features/accounting_audit/presentation/accounting_audit_page.dart`
- `test/accounting_audit/accounting_audit_report_test.dart`

## Exact verified GitHub CI result

The source commit **`9208267267410a65553ee971ecb7e4e0c4c18dfb`** passed:

https://github.com/yazan-amleh/electrical_parts_store_v2/actions/runs/39949158671

- Flutter tests: **110 passed**
- Firestore/Storage security rules tests: **20 passed**
- Node Functions/Firebase Emulator tests: **85 passed; 0 failed**
- Dart formatting, Flutter analyzer, Web Release compilation: **PASS**

Included new checks for the 4,101-record paginated scan, exact page boundaries, direct journal line traversal across journals, wrong store ID on a nested ledger line, product valuation matching inventory GL, detecting tampered product valuation, unverified opening stock, and >200 audit errors. A preceding run exposed a wrong checked-line count when a malformed journal line was skipped; that defect was fixed before the green source commit.

## Remaining risks and required follow-up

- The callable **is not an unlimited background reconciliation**: it fails closed after any per-collection/overall cap. Large stores require checkpointed, resumable jobs, throttling and retained results. A single callable may also time out before reaching its cap. Do not claim unlimited scale.
- Multiple source collections are read at different times. A concurrent posting may produce a transient difference or obscure one. Formal accounting certification requires a controlled read-time snapshot or a source write freeze and documented reconciliation period. No such freeze is implemented.
- Direct journal scans follow **existing journal headers**. An orphan nested line whose parent journal header was deleted may remain undetected. A separate orphan-line discovery/export pass is necessary before claiming full journal completeness.
- Stored historical stock may have an opening value that predates movement capture. The reported `INVENTORY_OPENING_SOURCE_UNVERIFIED` must be resolved with original source documents rather than fabricated adjustments. Inventory valuation and full depletion rounding require a finance-approved accounting policy.
- Cross-feature writes/reversals, returns/refunds, multi-currency journals, account origin/audit trail, 200+ detailed issue retrieval and real Firebase end-to-end testing remain open.
- No automatic correction of discrepancies, no mass balance recalculation, and **no deployment/merge**.

## Next execution gate

Implement an independently verifiable, **checkpointed full-history reconciliation/export** for stores above the bounded callable limit, with a consistent reporting cut-off, orphan journal-line discovery, and explicit finance approval for opening balance treatment and inventory depletion rounding.
