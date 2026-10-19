import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/features/parties/domain/domain.dart';

void main() {
  test('customer debit entry exposes the receivable delta', () {
    final entry = PartyLedgerEntry(
      id: 'sale-1-customer',
      storeId: 'store-1',
      partyType: PartyType.customer,
      partyId: 'customer-1',
      sourceType: 'sale',
      sourceId: 'sale-1',
      postedAt: DateTime.utc(2026, 1, 1),
      debit: const Money(minorUnits: 1180, currency: 'ILS'),
      credit: const Money(minorUnits: 0, currency: 'ILS'),
    );

    expect(entry.balanceDelta.minorUnits, 1180);
  });

  test('a party ledger entry cannot contain both sides', () {
    expect(
      () => PartyLedgerEntry(
        id: 'entry-1',
        storeId: 'store-1',
        partyType: PartyType.supplier,
        partyId: 'supplier-1',
        sourceType: 'purchase',
        sourceId: 'purchase-1',
        postedAt: DateTime.utc(2026, 1, 1),
        debit: const Money(minorUnits: 100, currency: 'ILS'),
        credit: const Money(minorUnits: 100, currency: 'ILS'),
      ),
      throwsArgumentError,
    );
  });
}
