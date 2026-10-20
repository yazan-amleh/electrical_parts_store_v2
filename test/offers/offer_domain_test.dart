import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/core/quantity/quantity.dart';
import 'package:electrical_parts_store_v2/features/offers/domain/entities/offer.dart';
import 'package:electrical_parts_store_v2/features/offers/domain/entities/offer_line.dart';
import 'package:electrical_parts_store_v2/features/offers/domain/entities/offer_order.dart';
import 'package:electrical_parts_store_v2/features/offers/domain/enums/offer_order_status.dart';
import 'package:electrical_parts_store_v2/features/offers/domain/enums/offer_price_type.dart';

void main() {
  OfferLine line({
    required String id,
    required int original,
    required int finalPrice,
    required int quantityMilliUnits,
  }) {
    return OfferLine(
      id: id,
      productId: 'product-$id',
      productName: 'Product $id',
      originalUnitPrice: Money(minorUnits: original),
      finalUnitPrice: Money(minorUnits: finalPrice),
      quantity: Quantity(milliUnits: quantityMilliUnits),
      unitFactorToBase: const Quantity(milliUnits: 1000),
      priceType: OfferPriceType.retail,
    );
  }

  test('calculates line, global, and final offer totals exactly', () {
    final offer = Offer(
      id: 'offer-1',
      storeId: 'store-1',
      offerNumber: 'OFFER-1',
      name: 'Summer bundle',
      lines: [
        line(
          id: 'one',
          original: 1000,
          finalPrice: 900,
          quantityMilliUnits: 2000,
        ),
        line(
          id: 'two',
          original: 2500,
          finalPrice: 2000,
          quantityMilliUnits: 1500,
        ),
      ],
      createdAt: DateTime.utc(2026, 1, 1),
      isActive: true,
      globalDiscount: const Money(minorUnits: 300),
    );

    expect(offer.originalTotal, const Money(minorUnits: 5750));
    expect(offer.lineDiscountTotal, const Money(minorUnits: 950));
    expect(offer.totalDiscount, const Money(minorUnits: 1250));
    expect(offer.totalFinal, const Money(minorUnits: 4500));
  });

  test('rejects a line whose final price exceeds its original price', () {
    expect(
      () => line(
        id: 'invalid',
        original: 1000,
        finalPrice: 1001,
        quantityMilliUnits: 1000,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects a global discount greater than line total', () {
    expect(
      () => Offer(
        id: 'offer-2',
        storeId: 'store-1',
        offerNumber: 'OFFER-2',
        name: 'Invalid bundle',
        lines: [
          line(
            id: 'one',
            original: 1000,
            finalPrice: 900,
            quantityMilliUnits: 1000,
          ),
        ],
        createdAt: DateTime.utc(2026, 1, 1),
        isActive: true,
        globalDiscount: const Money(minorUnits: 101),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('confirmed order requires and preserves posted sale identifiers', () {
    final pending = OfferOrder(
      id: 'order-1',
      storeId: 'store-1',
      orderNumber: 'OO-1',
      offerId: 'offer-1',
      offerNumber: 'OFFER-1',
      customerId: 'customer-1',
      customerName: 'Customer',
      lines: [
        line(
          id: 'one',
          original: 1000,
          finalPrice: 900,
          quantityMilliUnits: 1000,
        ),
      ],
    );

    final confirmed = pending.copyWith(
      status: OfferOrderStatus.confirmed,
      saleId: 'sale-1',
      journalEntryId: 'journal-1',
    );

    expect(confirmed.status, OfferOrderStatus.confirmed);
    expect(confirmed.saleId, 'sale-1');
    expect(confirmed.journalEntryId, 'journal-1');
    expect(confirmed.total, const Money(minorUnits: 900));
  });
}
