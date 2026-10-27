import 'dart:convert';

import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/features/reports/domain/entities/sales_invoice_report.dart';
import 'package:electrical_parts_store_v2/features/reports/presentation/sales_invoice_selection_export.dart';
import 'package:flutter_test/flutter_test.dart';

SalesInvoiceSummary sale({
  String id = 'sale-1',
  String customer = 'customer-1',
  String currency = 'ILS',
}) {
  return SalesInvoiceSummary(
    id: id,
    storeId: 'store-a',
    postedAt: DateTime.utc(2026, 10, 27, 13),
    customerId: customer,
    paymentMethod: 'cash',
    subtotal: Money(minorUnits: 10000, currency: currency),
    tax: Money(minorUnits: 1600, currency: currency),
    total: Money(minorUnits: 11600, currency: currency),
    cost: Money(minorUnits: 6000, currency: currency),
    journalEntryId: 'journal-1',
    description: 'Read-only report',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CSV includes exactly selected posted invoices and currency', () {
    const exporter = SalesInvoiceSelectionExport();
    final csv = exporter.csv(
      invoices: [
        sale(id: 'selected-1'),
        sale(id: 'selected-2', currency: 'USD')
      ],
      customerNames: const {'customer-1': 'عميل'},
    );
    expect(csv, contains('selected-1'));
    expect(csv, contains('selected-2'));
    expect(csv, contains('"ILS"'));
    expect(csv, contains('"USD"'));
    expect(csv, contains('"11600"'));
    expect(csv, isNot(contains('unselected')));
  });

  test('CSV quotes and formula-protects customer names and invoice IDs', () {
    const exporter = SalesInvoiceSelectionExport();
    final csv = exporter.csv(
      invoices: [sale(id: '=SUM(2,3)')],
      customerNames: const {'customer-1': '  @HYPERLINK("unsafe")'},
    );
    expect(csv, contains("'=SUM(2,3)"));
    expect(csv, contains("'  @HYPERLINK"));
    expect(csv, contains('""unsafe""'));
  });

  test('PDF is generated offline using bundled Arabic font', () async {
    const exporter = SalesInvoiceSelectionExport();
    final bytes = await exporter.pdf(
      invoices: [sale()],
      customerNames: const {'customer-1': 'عميل'},
      storeLabel: 'متجر الاختبار',
    );
    expect(bytes.length, greaterThan(700));
    expect(latin1.decode(bytes.take(4).toList()), '%PDF');
  });
}
