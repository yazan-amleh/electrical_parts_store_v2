import 'dart:async';
import 'dart:convert';

import 'package:electrical_parts_store_v2/core/idempotency/idempotency_key.dart';
import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/core/quantity/quantity.dart';
import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/inventory/data/exporters/pdf_product_history_document_builder.dart';
import 'package:electrical_parts_store_v2/features/inventory/domain/entities/inventory_movement.dart';
import 'package:electrical_parts_store_v2/features/inventory/domain/entities/product.dart';
import 'package:electrical_parts_store_v2/features/inventory/domain/enums/inventory_movement_type.dart';
import 'package:electrical_parts_store_v2/features/inventory/domain/repositories/inventory_repository.dart';
import 'package:electrical_parts_store_v2/features/inventory/domain/repositories/product_repository.dart';
import 'package:electrical_parts_store_v2/features/inventory/presentation/product_details_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Product _product({String storeId = 'store-a', String id = 'part-1'}) => Product(
      id: id,
      storeId: storeId,
      name: 'مفتاح كهربائي',
      purchasePrice: const Money(minorUnits: 250),
      sellingPrice: const Money(minorUnits: 550),
      wholesalePrice: const Money(minorUnits: 450),
      quantityOnHand: const Quantity.fromMilliUnits(3000),
      minimumQuantity: const Quantity.fromMilliUnits(4000),
      categoryId: 'category-a',
      sku: 'SW-1',
      barcode: '300111',
      brand: 'Brand',
      location: 'مستودع أ',
    );

InventoryMovement _movement({
  String id = 'move-1',
  String productId = 'part-1',
  String storeId = 'store-a',
  int milli = 1000,
  InventoryMovementType type = InventoryMovementType.purchaseReceipt,
  String sourceId = 'PO-33',
}) =>
    InventoryMovement(
      id: id,
      productId: productId,
      storeId: storeId,
      type: type,
      quantityDelta: Quantity.fromMilliUnits(milli),
      unitCost: const Money(minorUnits: 250),
      idempotencyKey: IdempotencyKey('idem-$id'),
      sourceType: 'purchase',
      sourceId: sourceId,
      description: 'حركة تجريبية',
      occurredAt: DateTime.utc(2026, 10, 1),
    );

class _Products implements ProductRepository {
  final requestIds = <String>[];
  Product result = _product();
  Completer<Result<Product>>? pending;

  @override
  Future<Result<Product>> getProduct({
    required StoreContext context,
    required String productId,
  }) {
    requestIds.add('${context.storeId}:$productId');
    return pending?.future ?? Future.value(Success(result));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _History implements InventoryRepository {
  List<InventoryMovement> data = [];
  final calls = <String>[];
  Completer<Result<List<InventoryMovement>>>? pending;

  @override
  Future<Result<List<InventoryMovement>>> getMovements({
    required StoreContext context,
    String? productId,
    int limit = 100,
  }) {
    calls.add('${context.storeId}:$productId:$limit');
    return pending?.future ?? Future.value(Success(data));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _page(
  _Products products,
  _History? history,
  String storeId, {
  String productId = 'part-1',
  VoidCallback? onEdit,
}) =>
    MaterialApp(
      home: ProductDetailsPage(
        key: const ValueKey('product-details'),
        productId: productId,
        contextScope: StoreContext(storeId: storeId, userId: 'user-1'),
        productRepository: products,
        inventoryRepository: history,
        onEdit: onEdit,
      ),
    );

void main() {
  testWidgets('V1 product detail shows rich data, stock alert and history',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final products = _Products();
    final history = _History()
      ..data = [
        _movement(),
        _movement(
          id: 'move-2',
          milli: -500,
          type: InventoryMovementType.saleIssue,
          sourceId: 'SALE-7',
        ),
      ];
    await tester.pumpWidget(_page(products, history, 'store-a'));
    await tester.pumpAndSettle();
    expect(find.text('تفاصيل الصنف'), findsOneWidget);
    expect(find.text('مفتاح كهربائي'), findsWidgets);
    expect(find.text('SW-1'), findsOneWidget);
    expect(
        find.textContaining('تنبيه: الصنف عند حد إعادة الطلب'), findsOneWidget);
    expect(find.text('سجل حركات الصنف'), findsOneWidget);
    expect(find.text('الحركات المطابقة: 2'), findsOneWidget);
    expect(find.text('وارد في المعروض: 1.000'), findsOneWidget);
    expect(find.text('صادر في المعروض: 0.500'), findsOneWidget);
    expect(find.byTooltip('تعديل الصنف'), findsNothing);
    expect(history.calls.single, 'store-a:part-1:500');

    await tester.enterText(
      find.byKey(const ValueKey('product-history-search')),
      'SALE-7',
    );
    await tester.pumpAndSettle();
    expect(find.text('الحركات المطابقة: 1'), findsOneWidget);
    expect(find.text('وارد في المعروض: 0.000'), findsOneWidget);
    expect(find.text('صادر في المعروض: 0.500'), findsOneWidget);
  });

  testWidgets('rejects cross-store product response', (tester) async {
    final products = _Products()..result = _product(storeId: 'store-b');
    final history = _History();
    await tester.pumpWidget(_page(products, history, 'store-a'));
    await tester.pumpAndSettle();
    expect(find.textContaining('تم رفض بيانات صنف'), findsOneWidget);
    expect(find.text('سجل حركات الصنف'), findsNothing);
    expect(history.calls, isEmpty);
  });

  testWidgets('rejects cross-product or cross-store movement data',
      (tester) async {
    final products = _Products();
    final history = _History()..data = [_movement(storeId: 'store-b')];
    await tester.pumpWidget(_page(products, history, 'store-a'));
    await tester.pumpAndSettle();
    expect(find.textContaining('تم رفض حركات تخص صنفًا'), findsOneWidget);
    expect(find.byTooltip('طباعة كشف الصنف'), findsOneWidget);
    final button = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('طباعة كشف الصنف'),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('late old-store request cannot reveal previous product',
      (tester) async {
    final products = _Products();
    products.pending = Completer<Result<Product>>();
    await tester.pumpWidget(_page(products, null, 'store-a'));
    await tester.pump();
    await tester.pumpWidget(_page(products, null, 'store-b'));
    await tester.pump();
    products.pending!.complete(Success(_product()));
    await tester.pumpAndSettle();
    expect(find.text('مفتاح كهربائي'), findsNothing);
    expect(find.textContaining('تم رفض بيانات صنف'), findsOneWidget);
  });

  test('PDF uses only posted product movements and rejects mixed tenants',
      () async {
    final builder = PdfProductHistoryDocumentBuilder();
    final bytes = await builder.build(
      product: _product(),
      movements: [_movement()],
      expectedStoreId: 'store-a',
      historyMayBeTruncated: true,
    );
    expect(bytes.length, greaterThan(1000));
    expect(latin1.decode(bytes.take(4).toList()), '%PDF');
    await expectLater(
      builder.build(
        product: _product(),
        movements: [_movement(productId: 'different')],
        expectedStoreId: 'store-a',
        historyMayBeTruncated: false,
      ),
      throwsStateError,
    );
    await expectLater(
      builder.build(
        product: _product(),
        movements: const [],
        expectedStoreId: 'store-b',
        historyMayBeTruncated: false,
      ),
      throwsStateError,
    );
  });
}
