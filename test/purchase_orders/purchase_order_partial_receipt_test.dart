import 'package:electrical_parts_store_v2/core/errors/failure.dart';
import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/core/quantity/quantity.dart';
import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/authenticated_user.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/store_membership.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/enums/store_role.dart';
import 'package:electrical_parts_store_v2/features/inventory/domain/entities/product.dart';
import 'package:electrical_parts_store_v2/features/inventory/domain/repositories/product_repository.dart';
import 'package:electrical_parts_store_v2/features/parties/domain/entities/party.dart';
import 'package:electrical_parts_store_v2/features/parties/domain/enums/party_type.dart';
import 'package:electrical_parts_store_v2/features/parties/domain/repositories/party_repository.dart';
import 'package:electrical_parts_store_v2/features/purchase_orders/domain/entities/purchase_order.dart';
import 'package:electrical_parts_store_v2/features/purchase_orders/domain/entities/purchase_order_line.dart';
import 'package:electrical_parts_store_v2/features/purchase_orders/domain/entities/purchase_order_receipt.dart';
import 'package:electrical_parts_store_v2/features/purchase_orders/domain/enums/purchase_order_status.dart';
import 'package:electrical_parts_store_v2/features/purchase_orders/domain/repositories/purchase_order_repository.dart';
import 'package:electrical_parts_store_v2/features/purchase_orders/presentation/purchase_orders_page.dart';
import 'package:electrical_parts_store_v2/features/purchases/domain/entities/purchase_posting_plan.dart';
import 'package:electrical_parts_store_v2/features/purchases/domain/enums/purchase_payment_method.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Orders implements PurchaseOrderRepository {
  _Orders({this.failFirst = false});

  final bool failFirst;
  final receipts = <PurchaseOrderReceiptRequest>[];

  PurchaseOrder get order => PurchaseOrder(
        id: 'order-1',
        storeId: 'store-1',
        orderNumber: 'PO-100',
        supplierId: 'supplier-1',
        supplierName: 'Supplier',
        orderedAt: DateTime.utc(2026, 10, 28),
        status: PurchaseOrderStatus.pending,
        lines: [
          PurchaseOrderLine(
            id: 'line-1',
            productId: 'product-1',
            productName: 'Cable',
            quantity: const Quantity.fromMilliUnits(2000),
            unitFactorToBase: const Quantity.fromMilliUnits(1000),
            unitCost: const Money(minorUnits: 700),
            receivedQuantity: const Quantity.fromMilliUnits(500),
            unitName: 'm',
          ),
        ],
      );

  @override
  Future<Result<List<PurchaseOrder>>> getPurchaseOrders({
    required StoreContext context,
  }) async {
    return Success(<PurchaseOrder>[order]);
  }

  @override
  Future<Result<PurchaseOrderReceipt>> receivePurchaseOrder({
    required StoreContext context,
    required PurchaseOrder order,
    required PurchaseOrderReceiptRequest receipt,
    required PurchasePaymentMethod paymentMethod,
    required PurchasePostingAccounts accounts,
    required int taxMinorUnits,
  }) async {
    receipts.add(receipt);
    if (failFirst && receipts.length == 1) {
      return const FailureResult<PurchaseOrderReceipt>(
        InfrastructureFailure('Unknown network outcome'),
      );
    }
    return Success(
      PurchaseOrderReceipt(
        orderId: order.id,
        purchaseId: receipt.receiptId,
        journalEntryId: '${receipt.receiptId}-journal',
        completed: false,
        orderStatus: 'pending',
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Products implements ProductRepository {
  @override
  Future<Result<List<Product>>> getProducts({
    required StoreContext context,
    bool includeInactive = false,
  }) async {
    return Success(<Product>[
      Product(
        id: 'product-1',
        storeId: context.storeId,
        name: 'Cable',
        purchasePrice: const Money(minorUnits: 700),
        sellingPrice: const Money(minorUnits: 900),
        wholesalePrice: const Money(minorUnits: 850),
        quantityOnHand: const Quantity.fromMilliUnits(1000),
        minimumQuantity: const Quantity.fromMilliUnits(0),
        categoryId: 'category-1',
      ),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Parties implements PartyRepository {
  @override
  Future<Result<List<Party>>> getParties({
    required StoreContext context,
    required PartyType type,
    bool includeInactive = false,
  }) async {
    return Success(<Party>[
      Party(
        id: 'supplier-1',
        storeId: context.storeId,
        type: PartyType.supplier,
        name: 'Supplier',
      ),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _user = AuthenticatedUser(
  id: 'user-1',
  email: 'test@example.com',
);
const _membership = StoreMembership(
  storeId: 'store-1',
  userId: 'user-1',
  role: StoreRole.owner,
);

Widget _page(_Orders repository) {
  return MaterialApp(
    home: Scaffold(
      body: PurchaseOrdersPage(
        repository: repository,
        productRepository: _Products(),
        partyRepository: _Parties(),
        user: _user,
        membership: _membership,
      ),
    ),
  );
}

Future<void> _openReceiveDialog(
  WidgetTester tester,
  _Orders repository,
) async {
  await tester.pumpWidget(_page(repository));
  await tester.pumpAndSettle();

  expect(find.textContaining('PO-100'), findsOneWidget);
  await tester.tap(find.textContaining('PO-100'));
  await tester.pumpAndSettle();

  expect(find.textContaining('المستلم: 0.5'), findsOneWidget);
  await tester.tap(find.text('استلام كمية إضافية'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('purchase orders load automatically on first entry',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_page(_Orders()));
    await tester.pumpAndSettle();

    expect(find.textContaining('PO-100'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('partial receipt submits only the selected remaining quantity',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _Orders();
    await _openReceiveDialog(tester, repository);

    final quantity = find.byKey(const ValueKey('po-receipt-qty-line-1'));
    expect(quantity, findsOneWidget);
    await tester.enterText(quantity, '0.5');
    await tester.tap(find.text('استلام وترحيل'));
    await tester.pumpAndSettle();

    expect(repository.receipts, hasLength(1));
    final receipt = repository.receipts.single;
    expect(receipt.lines, isNotNull);
    expect(receipt.lines, hasLength(1));
    expect(receipt.lines!.single.lineId, 'line-1');
    expect(receipt.lines!.single.quantityMilliUnits, 500);
  });

  testWidgets('unknown receipt result retries the exact same receipt command',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _Orders(failFirst: true);
    await _openReceiveDialog(tester, repository);

    await tester.enterText(
      find.byKey(const ValueKey('po-receipt-qty-line-1')),
      '0.5',
    );
    await tester.tap(find.text('استلام وترحيل'));
    await tester.pumpAndSettle();

    expect(repository.receipts, hasLength(1));
    final first = repository.receipts.single;

    await tester.tap(find.textContaining('PO-100'));
    await tester.pumpAndSettle();
    expect(find.text('إعادة نفس الاستلام'), findsOneWidget);
    await tester.tap(find.text('إعادة نفس الاستلام'));
    await tester.pumpAndSettle();

    expect(repository.receipts, hasLength(2));
    final second = repository.receipts.last;
    expect(identical(first, second), isTrue);
    expect(second.receiptId, first.receiptId);
    expect(second.idempotencyKey.value, first.idempotencyKey.value);
    expect(second.postedAt, first.postedAt);
    expect(
      second.lines!.single.quantityMilliUnits,
      first.lines!.single.quantityMilliUnits,
    );
  });
}
