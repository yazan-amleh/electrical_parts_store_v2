import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/core/quantity/quantity.dart';
import 'package:electrical_parts_store_v2/features/inventory/domain/entities/inventory_count.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> raw({
    String store = 'store-a',
    String status = 'draft',
    List<Map<String, dynamic>>? items,
  }) =>
      <String, dynamic>{
        'id': 'count-1',
        'storeId': store,
        'status': status,
        'revision': 1,
        'createdBy': 'worker',
        'items': items ??
            [
              {
                'productId': 'one',
                'productName': 'مفتاح',
                'systemQuantityMilliUnits': 2000,
                'actualQuantityMilliUnits': 1500,
                'currency': 'ILS',
                'unitCostMinorUnits': 500,
                'reviewed': true,
                'reason': 'تلف',
              },
              {
                'productId': 'two',
                'productName': 'قاطع',
                'systemQuantityMilliUnits': 2000,
                'actualQuantityMilliUnits': 3000,
                'currency': 'USD',
                'unitCostMinorUnits': 300,
                'reviewed': true,
                'reason': 'موجود بالمستودع',
              },
            ],
      };

  test('stocktake differences use exact milliunits and isolated currencies',
      () {
    final count = InventoryCount.fromMap('count-1', raw(), 'store-a');
    expect(count.canComplete, isTrue);
    expect(count.reviewedItems, 2);
    expect(
      count.items.first.difference,
      const Quantity.fromMilliUnits(-500),
    );
    expect(
      count.estimatedDifferenceByCurrency,
      {
        'ILS': const Money(minorUnits: -250),
        'USD': const Money(minorUnits: 300, currency: 'USD')
      },
    );
    expect(count.status, InventoryCountStatus.draft);
  });

  test('unreviewed or missing reason keeps count in draft', () {
    final one = InventoryCount.fromMap(
        'count-1',
        raw(items: [
          {
            'productId': 'one',
            'productName': 'مفتاح',
            'systemQuantityMilliUnits': 2000,
            'actualQuantityMilliUnits': 1500,
            'currency': 'ILS',
            'unitCostMinorUnits': 500,
            'reviewed': true,
            'reason': '',
          },
        ]),
        'store-a');
    expect(one.canComplete, isFalse);
    expect(one.items.single.difference?.formatted, ' -0.5'.trim());
    final two = InventoryCount.fromMap(
        'count-1',
        raw(items: [
          {
            'productId': 'one',
            'productName': 'مفتاح',
            'systemQuantityMilliUnits': 2000,
            'actualQuantityMilliUnits': null,
            'currency': 'ILS',
            'unitCostMinorUnits': 500,
            'reviewed': false,
          },
        ]),
        'store-a');
    expect(two.canComplete, isFalse);
  });

  test('cross-tenant, duplicate product and malformed quantity are rejected',
      () {
    expect(
      () => InventoryCount.fromMap('count-1', raw(store: 'store-b'), 'store-a'),
      throwsFormatException,
    );
    final item = raw()['items'] as List<Map<String, dynamic>>;
    expect(
      () => InventoryCount.fromMap(
          'count-1', raw(items: [item[0], item[0]]), 'store-a'),
      throwsFormatException,
    );
    final bad = {...item[0], 'actualQuantityMilliUnits': -10};
    expect(
      () => InventoryCount.fromMap('count-1', raw(items: [bad]), 'store-a'),
      throwsFormatException,
    );
  });
}
