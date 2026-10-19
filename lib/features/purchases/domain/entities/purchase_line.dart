import '../../../../core/money/money.dart';
import '../../../../core/quantity/quantity.dart';

class PurchaseLine {
  PurchaseLine({
    required this.id,
    required this.productId,
    required this.description,
    required this.quantity,
    required this.unitFactorToBase,
    required this.unitCost,
    required this.discount,
    this.unitId,
    this.unitName,
  }) {
    _ensureSafeIdentifier(id, 'Purchase line id');
    _ensureSafeIdentifier(productId, 'Product id');

    if (description.trim().isEmpty) {
      throw ArgumentError('Purchase line description is required.');
    }
    if (quantity.milliUnits <= 0) {
      throw ArgumentError('Purchase line quantity must be positive.');
    }
    if (unitFactorToBase.milliUnits <= 0) {
      throw ArgumentError('Purchase line unit factor must be positive.');
    }
    if (baseQuantity.isZero) {
      throw ArgumentError('Purchase line base quantity must be positive.');
    }
    if (unitCost.isNegative || discount.isNegative) {
      throw ArgumentError('Purchase line amounts cannot be negative.');
    }
    if (unitCost.currency != discount.currency) {
      throw ArgumentError('Purchase line amounts must use one currency.');
    }
    if (discount.minorUnits > grossTotal.minorUnits) {
      throw ArgumentError(
        'Purchase line discount cannot exceed its gross total.',
      );
    }
  }

  final String id;
  final String productId;
  final String description;
  final Quantity quantity;
  final Quantity unitFactorToBase;
  final Money unitCost;
  final Money discount;
  final String? unitId;
  final String? unitName;

  String get currency => unitCost.currency;

  Quantity get baseQuantity {
    final numerator = quantity.milliUnits * unitFactorToBase.milliUnits;
    final baseMilliUnits = (numerator + Quantity.scale ~/ 2) ~/ Quantity.scale;
    return Quantity.fromMilliUnits(baseMilliUnits);
  }

  Money get grossTotal => _multiply(unitCost, baseQuantity);

  Money get total => grossTotal - discount;

  static Money _multiply(Money amount, Quantity quantity) {
    final numerator = amount.minorUnits * quantity.milliUnits;
    final scaled = (numerator + Quantity.scale ~/ 2) ~/ Quantity.scale;
    return Money(minorUnits: scaled, currency: amount.currency);
  }

  static void _ensureSafeIdentifier(String value, String label) {
    if (value.trim().isEmpty) {
      throw ArgumentError('$label is required.');
    }
    if (value.contains('/')) {
      throw ArgumentError('$label cannot contain a slash.');
    }
  }
}
