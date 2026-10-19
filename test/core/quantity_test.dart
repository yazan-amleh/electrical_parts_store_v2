import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/core/quantity/quantity.dart';

void main() {
  test('stores decimal quantities without binary floating point drift', () {
    final quantity = Quantity.fromDouble(1.375);

    expect(quantity.milliUnits, 1375);
    expect(quantity.formatted, '1.375');
  });

  test('supports exact addition and subtraction', () {
    final first = Quantity.fromString('1.5');
    final second = Quantity.fromString('0.25');

    expect((first + second).milliUnits, 1750);
    expect((first - second).milliUnits, 1250);
  });
}
