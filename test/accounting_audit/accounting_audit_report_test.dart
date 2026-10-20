import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/features/accounting_audit/domain/entities/accounting_audit_report.dart';

void main() {
  test('parses a healthy audit report with exact counters', () {
    final report = AccountingAuditReport.fromMap({
      'storeId': 'store-1',
      'generatedAt': '2026-01-02T03:04:05.000Z',
      'checked': {
        'accounts': 12,
        'journalEntries': 7,
        'journalLines': 14,
        'parties': 3,
        'partyLedgerEntries': 5,
        'products': 9,
        'inventoryMovements': 11,
      },
      'issues': const [],
    });

    expect(report.storeId, 'store-1');
    expect(report.isHealthy, isTrue);
    expect(report.errorCount, 0);
    expect(report.warningCount, 0);
    expect(report.accountsChecked, 12);
    expect(report.journalEntriesChecked, 7);
    expect(report.inventoryMovementsChecked, 11);
  });

  test('keeps warnings visible without hiding accounting errors', () {
    final report = AccountingAuditReport.fromMap({
      'storeId': 'store-1',
      'checked': const <String, dynamic>{},
      'issues': [
        {
          'code': 'HEADER_ACCOUNT_HAS_BALANCE',
          'scope': 'accountBalance',
          'referenceId': '1100',
          'message': 'Header account has a direct balance.',
          'severity': 'warning',
          'valueKind': 'minorUnits',
          'currency': 'ILS',
          'expected': 0,
          'actual': 1000,
        },
        {
          'code': 'ACCOUNT_DEBIT_MISMATCH',
          'scope': 'accountBalance',
          'referenceId': '1110',
          'message': 'Debit mismatch.',
          'severity': 'error',
          'valueKind': 'minorUnits',
          'currency': 'ILS',
          'expected': 1000,
          'actual': 900,
        },
      ],
    });

    expect(report.isHealthy, isFalse);
    expect(report.errorCount, 1);
    expect(report.warningCount, 1);
    expect(
      report.issues
          .singleWhere((issue) => issue.code == 'ACCOUNT_DEBIT_MISMATCH')
          .expected,
      1000,
    );
  });
}
