import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/features/reports/domain/entities/operational_report.dart';
import 'package:electrical_parts_store_v2/features/reports/presentation/operational_report_export.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

OperationalReport _report({bool truncated = false}) {
  final from = DateTime.utc(2026, 10, 1);
  return OperationalReport(
    from: from,
    to: DateTime.utc(2026, 10, 31),
    salesRevenue: const Money(minorUnits: 10000),
    salesCost: const Money(minorUnits: 4200),
    purchasesTotal: const Money(minorUnits: 6500),
    expensesTotal: const Money(minorUnits: 1200),
    salesCount: 1,
    salesReturnCount: 0,
    purchasesCount: 1,
    purchaseReturnCount: 0,
    expensesCount: 1,
    salesByPaymentMethod: const {'cash': 1},
    expensesByPaymentMethod: const {'bank': 1},
    transactions: [
      ReportTransaction(
        id: 'sale-a',
        postedAt: from,
        source: 'sale',
        amount: const Money(minorUnits: 11700),
        cost: const Money(minorUnits: 4200),
        tax: const Money(minorUnits: 1700),
        description: '=INJECT',
        paymentMethod: 'cash',
      ),
      ReportTransaction(
        id: 'purchase-a',
        postedAt: from,
        source: 'purchase',
        amount: const Money(minorUnits: 6500),
        cost: const Money(minorUnits: 0),
        tax: const Money(minorUnits: 0),
        description: 'كابلات كهربائية',
        paymentMethod: 'bank',
      ),
      ReportTransaction(
        id: 'expense-a',
        postedAt: from,
        source: 'expense',
        amount: const Money(minorUnits: 1200),
        cost: const Money(minorUnits: 0),
        description: 'نقل',
        paymentMethod: 'bank',
      ),
    ],
    mayBeTruncated: truncated,
  );
}

void main() {
  const exporter = OperationalReportExport();

  test('V1 parity: source, payment and text filters are composable', () {
    final report = _report();
    final sales = const OperationalTransactionFilter(
      source: 'sale',
      paymentMethod: 'cash',
    ).apply(report.transactions);
    expect(sales.map((item) => item.id), ['sale-a']);
    expect(
      const OperationalTransactionFilter(
        paymentMethod: 'bank',
        search: 'كابلات',
      ).apply(report.transactions).map((item) => item.id),
      ['purchase-a'],
    );
    expect(
      const OperationalTransactionFilter(search: 'unlisted')
          .apply(report.transactions),
      isEmpty,
    );
  });

  test('XLSX separates full-period totals from filtered movements', () {
    final report = _report();
    final one = const OperationalTransactionFilter(source: 'sale')
        .apply(report.transactions);
    final bytes = exporter.xlsx(
      report: report,
      storeLabel: 'store-a',
      displayedTransactions: one,
      detailsFiltered: true,
    );
    final excel = Excel.decodeBytes(bytes);
    final summary = excel.tables['ملخص التقرير'];
    final movements = excel.tables['تفاصيل الحركات'];
    final payments = excel.tables['طرق الدفع'];

    expect(summary, isNotNull);
    expect(movements, isNotNull);
    expect(payments, isNotNull);
    expect(movements!.maxRows, 2);
    expect(movements.rows[1][0]?.value.toString(), contains('sale-a'));
    expect(movements.rows[1][3]?.value.toString(), contains("'=INJECT"));
    expect(payments!.maxRows, 3);
    final summaryValues = summary!.rows
        .map((row) => row.map((cell) => cell?.value.toString() ?? '').toList())
        .toList();
    expect(
      summaryValues.any(
        (row) => row.first.contains('صافي المبيعات') &&
            row[1].contains('100'),
      ),
      isTrue,
    );
    expect(
      summaryValues.any((row) => row.first.contains('الحركات المصدّرة') &&
          row[1].contains('1')),
      isTrue,
    );
  });

  test('truncated exports are marked explicitly; CSV blocks formula payload', () {
    final report = _report(truncated: true);
    final bytes = exporter.xlsx(
      report: report,
      storeLabel: 'store-b',
      displayedTransactions: report.transactions,
    );
    final excel = Excel.decodeBytes(bytes);
    final values = excel.tables['ملخص التقرير']!.rows
        .expand((row) => row)
        .map((cell) => cell?.value.toString() ?? '')
        .toList();
    expect(values.any((s) => s.contains('غير مكتمل')), isTrue);
    final csv = exporter.csv(report.transactions);
    expect(csv, contains('"\'=INJECT"'));
    expect(csv, contains('amount_minor_units'));
    expect(csv, contains('11700'));
    expect(csv, isNot(contains('100.00')));
  });
}
