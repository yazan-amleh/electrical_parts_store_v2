import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/core/quantity/quantity.dart';
import 'package:electrical_parts_store_v2/features/purchase_orders/domain/entities/purchase_order.dart';
import 'package:electrical_parts_store_v2/features/purchase_orders/domain/entities/purchase_order_line.dart';
import 'package:electrical_parts_store_v2/features/purchase_orders/domain/enums/purchase_order_status.dart';

void main() {
  final line = PurchaseOrderLine(
    id: 'line-1',
    productId: 'product-1',
    productName: 'Cable',
    quantity: Quantity.fromDouble(2),
    unitFactorToBase: const Quantity.fromMilliUnits(1000),
    unitCost: const Money(minorUnits: 500, currency: 'ILS'),
  );

  test('calculates the order total and remaining quantity exactly', () {
    final order = PurchaseOrder(
      id: 'order-1',
      storeId: 'store-1',
      orderNumber: 'PO-1',
      supplierId: 'supplier-1',
      supplierName: 'Supplier',
      orderedAt: DateTime.utc(2026, 1, 1),
      lines: <PurchaseOrderLine>[line],
      status: PurchaseOrderStatus.pending,
    );

    expect(order.total, const Money(minorUnits: 1000, currency: 'ILS'));
    expect(line.baseQuantity, Quantity.fromDouble(2));
    expect(line.remainingQuantity, Quantity.fromDouble(2));
    expect(order.canReceive, isTrue);
  });

  test('rejects a received quantity greater than the ordered quantity', () {
    expect(
      () => PurchaseOrderLine(
        id: 'line-1',
        productId: 'product-1',
        productName: 'Cable',
        quantity: Quantity.fromDouble(1),
        unitFactorToBase: const Quantity.fromMilliUnits(1000),
        unitCost: const Money(minorUnits: 500, currency: 'ILS'),
        receivedQuantity: Quantity.fromDouble(2),
      ),
      throwsArgumentError,
    );
  });

  test('rejects purchase orders with mixed currencies', () {
    expect(
      () => PurchaseOrder(
        id: 'order-1',
        storeId: 'store-1',
        orderNumber: 'PO-1',
        supplierId: 'supplier-1',
        supplierName: 'Supplier',
        orderedAt: DateTime.utc(2026, 1, 1),
        lines: <PurchaseOrderLine>[
          line,
          PurchaseOrderLine(
            id: 'line-2',
            productId: 'product-2',
            productName: 'Fuse',
            quantity: Quantity.fromDouble(1),
            unitFactorToBase: const Quantity.fromMilliUnits(1000),
            unitCost: const Money(minorUnits: 100, currency: 'USD'),
          ),
        ],
        status: PurchaseOrderStatus.pending,
      ),
      throwsArgumentError,
    );
  });
}
