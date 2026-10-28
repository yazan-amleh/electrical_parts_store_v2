import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/features/reports/domain/entities/operational_report.dart';

void main() {
  test('operational report derives gross and operating result', () {
    final report = OperationalReport(
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
      mayBeTruncated: false,
    );

    expect(report.grossProfit, const Money(minorUnits: 4000));
    expect(report.operatingResult, const Money(minorUnits: 2500));
    expect(report.transactionCount, 6);
  });

  test('sale and sale return expose revenue before output tax', () {
    final sale = ReportTransaction(
      id: 'sale-1',
      postedAt: DateTime.utc(2026, 1, 10),
      source: 'sale',
      amount: Money(minorUnits: 11600),
      cost: Money(minorUnits: 6000),
      tax: Money(minorUnits: 1600),
      description: null,
      paymentMethod: 'cash',
    );
    final saleReturn = ReportTransaction(
      id: 'return-1',
      postedAt: DateTime.utc(2026, 1, 11),
      source: 'saleReturn',
      amount: Money(minorUnits: -5800),
      cost: Money(minorUnits: -3000),
      tax: Money(minorUnits: -800),
      description: null,
      paymentMethod: 'cash',
    );

    expect(sale.amountBeforeTax, const Money(minorUnits: 10000));
    expect(saleReturn.amountBeforeTax, const Money(minorUnits: -5000));
  });

  test('operational transaction count includes sale and purchase returns', () {
    final report = OperationalReport(
      from: DateTime.utc(2026, 1, 1),
      to: DateTime.utc(2026, 1, 31),
      salesRevenue: const Money(minorUnits: 5000),
      salesCost: const Money(minorUnits: 3000),
      purchasesTotal: const Money(minorUnits: 0),
      expensesTotal: const Money(minorUnits: 0),
      salesCount: 2,
      salesReturnCount: 1,
      purchasesCount: 2,
      purchaseReturnCount: 1,
      expensesCount: 0,
      salesByPaymentMethod: const {'cash': 2},
      expensesByPaymentMethod: const {},
      transactions: const <ReportTransaction>[],
      mayBeTruncated: false,
    );

    expect(report.transactionCount, 6);
  });

  test('purchase return reduces net purchases in its posting period', () {
    final purchase = ReportTransaction(
      id: 'purchase-1',
      postedAt: DateTime.utc(2026, 1, 10),
      source: 'purchase',
      amount: const Money(minorUnits: 11600),
      cost: const Money(minorUnits: 0),
      tax: const Money(minorUnits: 1600),
      description: null,
      paymentMethod: 'cash',
    );
    final purchaseReturn = ReportTransaction(
      id: 'purchase-return-1',
      postedAt: DateTime.utc(2026, 1, 12),
      source: 'purchaseReturn',
      amount: const Money(minorUnits: -5800),
      cost: const Money(minorUnits: 0),
      tax: const Money(minorUnits: -800),
      description: null,
      paymentMethod: 'cash',
    );

    final netPurchases = purchase.amount + purchaseReturn.amount;
    expect(netPurchases, const Money(minorUnits: 5800));
  });
}
