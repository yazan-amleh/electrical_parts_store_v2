import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/core/money/money.dart';

void main() {
  test('adds money using integer minor units', () {
    const first = Money(minorUnits: 1050);
    const second = Money(minorUnits: 250);

    expect(first + second, const Money(minorUnits: 1300));
  });

  test('rejects mixing currencies', () {
    const ils = Money(minorUnits: 100, currency: 'ILS');
    const usd = Money(minorUnits: 100, currency: 'USD');

    expect(() => ils + usd, throwsArgumentError);
  });
}
