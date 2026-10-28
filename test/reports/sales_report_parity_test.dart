import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/authenticated_user.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/store_membership.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/enums/store_role.dart';
import 'package:electrical_parts_store_v2/features/reports/domain/entities/sales_analytics.dart';
import 'package:electrical_parts_store_v2/features/reports/domain/entities/sales_invoice_report.dart';
import 'package:electrical_parts_store_v2/features/reports/domain/repositories/reports_repository.dart';
import 'package:electrical_parts_store_v2/features/reports/presentation/sales_analytics_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Reports implements ReportsRepository {
  final analytics = SalesAnalytics(
    from: DateTime.utc(2026, 10, 1),
    to: DateTime.utc(2026, 10, 31),
    salesRevenue: const Money(minorUnits: 11700),
    salesCost: const Money(minorUnits: 5000),
    salesCount: 1,
    paymentMethodCounts: const {'credit': 1},
    productRows: const [
      SalesAnalyticsRow(
        key: 'product-1',
        label: 'كابل كهربائي',
        quantityMilliUnits: 2000,
        revenue: Money(minorUnits: 10000),
        cost: Money(minorUnits: 5000),
      ),
    ],
    categoryRows: const [
      SalesAnalyticsRow(
        key: 'category-1',
        label: 'الكابلات',
        quantityMilliUnits: 2000,
        revenue: Money(minorUnits: 10000),
        cost: Money(minorUnits: 5000),
      ),
    ],
    customerRows: const [
      SalesAnalyticsRow(
        key: 'customer-1',
        label: 'عميل تجريبي',
        quantityMilliUnits: 0,
        revenue: Money(minorUnits: 11700),
        cost: Money(minorUnits: 5000),
      ),
    ],
    mayBeTruncated: false,
  );

  @override
  Future<Result<SalesAnalytics>> getSalesAnalytics({
    required StoreContext context,
    required DateTime from,
    required DateTime to,
    int limit = 500,
    int maxDocuments = 10000,
  }) async =>
      Success(analytics);

  @override
  Future<Result<SalesInvoiceReport>> getSalesInvoices({
    required StoreContext context,
    required DateTime from,
    required DateTime to,
    int limit = 250,
    int maxDocuments = 1000,
  }) async =>
      Success(SalesInvoiceReport(
        invoices: [
          SalesInvoiceSummary(
            id: 'sale-100',
            storeId: context.storeId,
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
        mayBeTruncated: false,
      ));

  @override
  Future<Result<List<SalesInvoiceDocument>>> getSalesInvoiceDocuments({
    required StoreContext context,
    required List<String> invoiceIds,
    int maxInvoices = 100,
  }) async =>
      Success([
        for (final id in invoiceIds)
          SalesInvoiceDocument(
            invoice: SalesInvoiceSummary(
              id: id,
              storeId: context.storeId,
              postedAt: DateTime.utc(2026, 10, 26),
              customerId: 'customer-1',
              paymentMethod: 'credit',
              subtotal: const Money(minorUnits: 10000),
              tax: const Money(minorUnits: 1700),
              total: const Money(minorUnits: 11700),
              cost: const Money(minorUnits: 5000),
              journalEntryId: '$id-journal',
            ),
            lines: const [
              SalesInvoiceLineSummary(
                id: 'line-1',
                productId: 'product-1',
                description: 'كابل كهربائي',
                quantityMilliUnits: 1000,
                unitPrice: Money(minorUnits: 10000),
                discount: Money(minorUnits: 0),
                total: Money(minorUnits: 10000),
                cost: Money(minorUnits: 5000),
                unitName: 'متر',
              ),
            ],
          ),
      ]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('sales report has V1 detail, product and customer tabs',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SalesAnalyticsPage(
          repository: _Reports(),
          documentBuilder: null,
          saleRepository: null,
          user: const AuthenticatedUser(
            id: 'user-1',
            email: 'test@example.com',
          ),
          membership: const StoreMembership(
            storeId: 'store-1',
            userId: 'user-1',
            role: StoreRole.owner,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(Tab, 'تفاصيل المبيعات'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'الأصناف الأكثر مبيعاً'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'ملخص العملاء'), findsOneWidget);
    expect(find.text('sale-100'), findsOneWidget);
    expect(find.text('sale-100-journal'), findsOneWidget);
    expect(find.byTooltip('طباعة الفاتورة sale-100'), findsOneWidget);
    expect(find.byTooltip('مشاركة PDF للفاتورة sale-100'), findsOneWidget);

    await tester.tap(find.text('اختيار عدة فواتير'));
    await tester.pumpAndSettle();
    expect(find.text('0 فاتورة مختارة'), findsOneWidget);
    await tester.tap(find.text('تحديد أول 100 مطابقة'));
    await tester.pumpAndSettle();
    expect(find.text('1 فاتورة مختارة'), findsOneWidget);
    expect(find.text('طباعة المحدد'), findsOneWidget);
    expect(find.text('مشاركة PDF للمحدد'), findsOneWidget);
    expect(find.text('نسخ CSV للمحدد'), findsOneWidget);
    await tester.tap(find.text('إلغاء التحديد'));
    await tester.pumpAndSettle();
    expect(find.text('0 فاتورة مختارة'), findsOneWidget);
    await tester.tap(find.text('إنهاء التحديد'));
    await tester.pumpAndSettle();
    expect(find.text('طباعة المحدد'), findsNothing);

    await tester.tap(find.widgetWithText(Tab, 'الأصناف الأكثر مبيعاً'));
    await tester.pumpAndSettle();
    expect(find.text('كابل كهربائي'), findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, 'ملخص العملاء'));
    await tester.pumpAndSettle();
    expect(find.text('عميل تجريبي'), findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, 'تفاصيل المبيعات'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'no-match');
    await tester.pump();
    expect(find.text('لا توجد فواتير مطابقة في البيانات المحمّلة.'),
        findsOneWidget);
    expect(find.text('sale-100'), findsNothing);
  });
}
