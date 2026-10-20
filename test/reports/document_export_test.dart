import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/core/idempotency/idempotency_key.dart';
import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/core/quantity/quantity.dart';
import 'package:electrical_parts_store_v2/features/categories/data/exporters/pdf_category_inventory_document_builder.dart';
import 'package:electrical_parts_store_v2/features/categories/domain/entities/category.dart';
import 'package:electrical_parts_store_v2/features/inventory/domain/entities/product.dart';
import 'package:electrical_parts_store_v2/features/payments/domain/enums/party_payment_method.dart';
import 'package:electrical_parts_store_v2/features/repairs/data/exporters/pdf_repair_document_builder.dart';
import 'package:electrical_parts_store_v2/features/repairs/domain/entities/repair_payment.dart';
import 'package:electrical_parts_store_v2/features/repairs/domain/entities/repair_request.dart';
import 'package:electrical_parts_store_v2/features/repairs/domain/enums/repair_payment_kind.dart';
import 'package:electrical_parts_store_v2/features/reports/data/exporters/pdf_report_document_builder.dart';
import 'package:electrical_parts_store_v2/features/reports/domain/entities/operational_report.dart';
import 'package:electrical_parts_store_v2/features/reports/domain/entities/sales_analytics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final from = DateTime.utc(2026, 1, 1);
  final to = DateTime.utc(2026, 1, 31);

  test('builds operational and sales analytics PDFs from calculated DTOs', () async {
    final builder = PdfReportDocumentBuilder();
    final operational = OperationalReport(
      from: from,
      to: to,
      salesRevenue: const Money(minorUnits: 10000),
      salesCost: const Money(minorUnits: 6000),
      purchasesTotal: const Money(minorUnits: 5000),
      expensesTotal: const Money(minorUnits: 1000),
      salesCount: 2,
      purchasesCount: 1,
      expensesCount: 1,
      salesByPaymentMethod: const {'cash': 2},
      expensesByPaymentMethod: const {'cash': 1},
      transactions: const <ReportTransaction>[],
      mayBeTruncated: false,
    );
    final analytics = SalesAnalytics(
      from: from,
      to: to,
      salesRevenue: const Money(minorUnits: 10000),
      salesCost: const Money(minorUnits: 6000),
      salesCount: 2,
      paymentMethodCounts: const {'cash': 2},
      productRows: const <SalesAnalyticsRow>[],
      categoryRows: const <SalesAnalyticsRow>[],
      customerRows: const <SalesAnalyticsRow>[],
      mayBeTruncated: false,
    );

    final operationalPdf = await builder.buildOperationalReport(
      report: operational,
      storeName: 'متجر الاختبار',
    );
    final analyticsPdf = await builder.buildSalesAnalyticsReport(
      analytics: analytics,
      storeName: 'متجر الاختبار',
    );

    expect(_isPdf(operationalPdf), isTrue);
    expect(_isPdf(analyticsPdf), isTrue);
  });

  test('builds repair request, payment receipt and category inventory PDFs', () async {
    final repair = RepairRequest(
      id: 'repair-1',
      storeId: 'store-1',
      idempotencyKey: const IdempotencyKey('repair-1'),
      customerId: 'customer-1',
      deviceName: 'Inverter',
      deviceModel: 'INV-100',
      problemDescription: 'لا يعمل',
      createdAt: from,
      receivedAt: from,
      expectedDeliveryDate: to,
      laborCost: const Money(minorUnits: 3000),
    );
    final payment = RepairPayment(
      id: 'payment-1',
      storeId: 'store-1',
      repairId: repair.id,
      customerId: repair.customerId,
      idempotencyKey: const IdempotencyKey('payment-1'),
      postedAt: from,
      kind: RepairPaymentKind.advance,
      paymentMethod: PartyPaymentMethod.cash,
      amount: const Money(minorUnits: 1000),
    );
    final category = const Category(
      id: 'category-1',
      storeId: 'store-1',
      name: 'كهربائيات',
    );
    final product = Product(
      id: 'product-1',
      storeId: 'store-1',
      name: 'فيوز',
      purchasePrice: const Money(minorUnits: 500),
      sellingPrice: const Money(minorUnits: 900),
      wholesalePrice: const Money(minorUnits: 700),
      quantityOnHand: Quantity.fromMilliUnits(2000),
      minimumQuantity: Quantity.fromMilliUnits(1),
      categoryId: category.id,
    );

    final repairBuilder = PdfRepairDocumentBuilder();
    final categoryBuilder = PdfCategoryInventoryDocumentBuilder();
    final repairPdf = await repairBuilder.buildRepairRequest(
      repair: repair,
      storeName: 'متجر الاختبار',
      customerName: 'عميل الاختبار',
      customerPhone: '0500000000',
    );
    final receiptPdf = await repairBuilder.buildPaymentReceipt(
      payment: payment,
      repair: repair,
      storeName: 'متجر الاختبار',
      customerName: 'عميل الاختبار',
      customerPhone: '0500000000',
    );
    final categoryPdf = await categoryBuilder.buildInventoryByCategory(
      categories: [category],
      productsByCategory: {
        category.id: [product],
      },
      storeName: 'متجر الاختبار',
    );

    expect(_isPdf(repairPdf), isTrue);
    expect(_isPdf(receiptPdf), isTrue);
    expect(_isPdf(categoryPdf), isTrue);
  });
}

bool _isPdf(Uint8List bytes) {
  if (bytes.length < 4) {
    return false;
  }
  return String.fromCharCodes(bytes.take(4)) == '%PDF';
}
