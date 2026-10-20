import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/features/reports/domain/entities/operational_report.dart';

void main() {
  test('operational report derives gross and operating result', () {
    const report = OperationalReport(
      from: DateTime.utc(2026, 1, 1),
      to: DateTime.utc(2026, 1, 31),
      salesRevenue: Money(minorUnits: 10000),
      salesCost: Money(minorUnits: 6000),
      purchasesTotal: Money(minorUnits: 9000),
      expensesTotal: Money(minorUnits: 1500),
      salesCount: 3,
      purchasesCount: 2,
      expensesCount: 1,
      salesByPaymentMethod: {'cash': 2, 'credit': 1},
      expensesByPaymentMethod: {'cash': 1},
      transactions: const <ReportTransaction>[],
    );

    expect(report.grossProfit, const Money(minorUnits: 4000));
    expect(report.operatingResult, const Money(minorUnits: 2500));
    expect(report.transactionCount, 6);
  });
}
