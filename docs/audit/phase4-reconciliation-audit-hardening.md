# Phase 4 — read-only accounting integrity audit hardening (2026-10-23)

## Scope and safe execution

Working branch `audit/systematic-v1-parity-20261023` from `v2/port-v1-complete`. V1 and its data are untouched. There were **no production Firebase writes, merges, historical balance recalculations, migrations or deployments**.

Previously `auditAccountingIntegrity` was a callable read-only audit comparing journal lines, account/party projections, inventory movements and product quantities. This step **repairs audit trustworthiness**, rather than altering financial source data.

## Defects found and repaired

1. **A-001 Mixed source lines:** `collectionGroup('lines').where('storeId', ==, storeId)` retrieves invoice-item documents nested under `sales` and `purchases` as well as actual journal lines. Some items may overlap `entryId` with a journal, making it possible to corrupt GL totals or falsely claim mismatches. Added exact path validator `stores/{storeId}/journal_entries/{entryId}/lines/{lineId}` and excluded unrelated collections. The checked journal-line count reflects filtered ledger lines.
2. **A-002 Silent numeric coercion:** `storedInt(value, 0)` in historical journal, GL/party balances and inventory aggregation could interpret missing, unsafe or malformed amounts as a genuine zero. Added `AUDIT_INVALID_INTEGER` issues instead of concealing corruption.
3. **A-003 Audit arithmetic:** unchecked cumulative debit/credit, quantity and inventory value could exceed JavaScript safe integer precision. Added `AUDIT_INTEGER_OVERFLOW` issue reporting.
4. **A-004 Balance identity:** the audited document ID, embedded account/party ID and tenant identity can disagree. Added explicit projection identity issue checks.
5. **A-005 Party net:** prior audit compared party debit/credit with source ledger but could ignore wrong stored net when debit/credit matched. Net must also reconcile.
6. **A-006 Unbounded reads and false 'healthy':** capped each source query to 4,001 documents. If any source exceeds 4,000, return `status: incomplete`, `complete: false`, and a hard error without claiming reconciliation. This is a defensive stop, **not** a full paginated audit.
7. **A-007 UI assurance:** Flutter audit model no longer treats incomplete scans as healthy. The visible report explicitly labels non-atomic source reads and uses a qualified 'no differences detected in scanned scope' message.

## Exact changed files

- `functions/accounting/audit_integrity.js`
- `functions/index.js`
- `functions/audit_integrity.test.js`
- `functions/accounting_audit_integrity.test.js`
- `functions/package.json`
- `lib/features/accounting_audit/domain/entities/accounting_audit_report.dart`
- `lib/features/accounting_audit/presentation/accounting_audit_page.dart`
- `test/accounting_audit/accounting_audit_report_test.dart`

## Confirmed CI outcome

Source commit `cd83889182b4558e1b0136f1f5b4670de45f7666` verified in GitHub Actions:

https://github.com/yazan-amleh/electrical_parts_store_v2/actions/runs/39946053479

- Flutter tests: **109 passed**
- Firestore/Storage security rules tests: **20 passed**
- Node Cloud Functions/Firestore emulator tests: **75 passed, 0 failed**
- Formatting, `flutter analyze`, `flutter build web --release`: **PASS**

Nine new tests total across backend pure functions (4), emulator (4), and Flutter audit DTO (1). Emulator tests verify journal-only source totals (with deliberately conflicting sale invoice line IDs), invalid persisted journal/GL money, tampered party net, and no mutations during audit.

## Known limitations — not certified

- **No point-in-time snapshot:** nine Firestore collection queries run concurrently, not in a single transaction/snapshot. Operational writes during an audit can create temporary differences. Response contains `consistency: 'non_atomic'`; clients should never present this as a formal certified reconciliation.
- **No full pagination:** source cap protects memory and avoids false healthy, but returns `incomplete` when over 4,000 documents for any scanned collection. Build checkpointed/paginated reconciliation with controlled snapshot boundaries before claiming support for large stores.
- **Collection-group index completeness:** the current `where('storeId', ...)` cannot fetch journal lines with missing/wrong `storeId`. If other lines from a journal exist, totals may expose a discrepancy, but completeness of all historical nested line documents is not yet proven. A direct journal-subcollection scan or export is required for certified full-history checks.
- **More integrity issues than 200:** issue list is capped; the returned issue count is not a comprehensive count beyond this.
- **Opening balances and historical movements:** do not presume all older inventory opening stock has matching inventory movements; absolute stock/GL reconciliation requires verified opening state and adjustments.
- **Multi-currency, reversal treatment, large data and concurrency** need independent accounting-policy tests.
- **Actual V2 Firebase device E2E / Android-iOS registration / V1 UI & complete feature parity** remain unfinished.
- Never repair differences by replacing stored values, and do not migrate V1 data.

## Next gate

Implement bounded, paginated historical reconciliation with consistency policy and explicit completeness guarantees, then audit inventory movement valuation/zero-stock rounding and return/refund semantics against exact V1 UI/business flows. Keep financial data read-only until the source of any mismatch is demonstrably understood.
