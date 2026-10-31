import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/features/reports/domain/entities/sales_analytics.dart';
import 'package:electrical_parts_store_v2/features/reports/domain/entities/sales_invoice_report.dart';
import 'package:electrical_parts_store_v2/features/reports/presentation/sales_excel_export.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const exporter = SalesExcelExport();

  test('invoice workbook contains the loaded invoice headers', () {
    final bytes = exporter.invoices(
      invoices: [
        SalesInvoiceSummary(
          id: 'sale-100',
          storeId: 'store-1',
          postedAt: DateTime.utc(2026, 10, 26),
          customerId: 'customer-1',
          paymentMethod: 'credit',
          subtotal: const Money(minorUnits: 10000),
          tax: const Money(minorUnits: 1700),
          total: const Money(minorUnits: 11700),
          cost: const Money(minorUnits: 5000),
          journalEntryId: 'sale-100-journal',
        ),
      ],
      customerNames: const {'customer-1': 'عميل تجريبي'},
    );

    final workbook = Excel.decodeBytes(bytes);
    final sheet = workbook.tables['تفاصيل المبيعات'];
    expect(sheet, isNotNull);
    expect(sheet!.maxRows, 2);
    expect(sheet.rows[1][0]?.value.toString(), contains('sale-100'));
    expect(sheet.rows[1][2]?.value.toString(), contains('عميل تجريبي'));
  });

  test('top-products workbook separates products and categories', () {
    final bytes = exporter.topProducts(
      products: const [
        SalesAnalyticsRow(
          key: 'product-1',
          label: 'كابل',
          quantityMilliUnits: 2000,
          revenue: Money(minorUnits: 10000),
          cost: Money(minorUnits: 5000),
        ),
      ],
      categories: const [
        SalesAnalyticsRow(
          key: 'category-1',
          label: 'كابلات',
          quantityMilliUnits: 2000,
          revenue: Money(minorUnits: 10000),
          cost: Money(minorUnits: 5000),
        ),
      ],
    );

    final workbook = Excel.decodeBytes(bytes);
    expect(workbook.tables['الأصناف الأكثر مبيعاً']?.maxRows, 2);
    expect(workbook.tables['المبيعات حسب التصنيف']?.maxRows, 2);
  });

  test('customer workbook includes payment method counts', () {
    final bytes = exporter.customers(
      customers: const [
        SalesAnalyticsRow(
          key: 'customer-1',
          label: 'عميل',
          quantityMilliUnits: 0,
          revenue: Money(minorUnits: 11700),
          cost: Money(minorUnits: 5000),
        ),
      ],
      paymentMethodCounts: const {'credit': 1},
    );

    final workbook = Excel.decodeBytes(bytes);
    expect(workbook.tables['ملخص العملاء']?.maxRows, 2);
    final paymentSheet = workbook.tables['طرق الدفع'];
    expect(paymentSheet?.maxRows, 2);
    expect(paymentSheet?.rows[1][0]?.value.toString(), contains('آجل'));
  });
}
