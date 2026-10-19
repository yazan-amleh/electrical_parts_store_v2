import '../../../../core/money/money.dart';
import '../../../../core/quantity/quantity.dart';

class SaleLine {
  SaleLine({
    required this.id,
    required this.productId,
    required this.description,
    required this.quantity,
    required this.unitFactorToBase,
    required this.unitPrice,
    required this.unitCost,
    required this.discount,
    this.unitId,
    this.unitName,
    this.isService = false,
  }) {
    _ensureSafeIdentifier(id, 'Sale line id');
    _ensureSafeIdentifier(productId, 'Product id');

    if (description.trim().isEmpty) {
      throw ArgumentError('Sale line description is required.');
    }
    if (quantity.milliUnits <= 0) {
      throw ArgumentError('Sale line quantity must be positive.');
    }
    if (unitFactorToBase.milliUnits <= 0) {
      throw ArgumentError('Sale line unit factor must be positive.');
    }
    if (!isService && baseQuantity.isZero) {
      throw ArgumentError('Sale line base quantity must be positive.');
    }
    if (unitPrice.isNegative || unitCost.isNegative) {
      throw ArgumentError('Sale line prices cannot be negative.');
    }
    if (discount.isNegative) {
      throw ArgumentError('Sale line discount cannot be negative.');
    }
    if (unitPrice.currency != unitCost.currency ||
        unitPrice.currency != discount.currency) {
      throw ArgumentError('Sale line amounts must use one currency.');
    }
    if (isService && !unitCost.isZero) {
      throw ArgumentError('A service line cannot carry inventory cost.');
    }
    if (discount.minorUnits > grossTotal.minorUnits) {
      throw ArgumentError('Sale line discount cannot exceed its gross total.');
    }
  }

  final String id;
  final String productId;
  final String description;
  final Quantity quantity;
  final Quantity unitFactorToBase;
  final Money unitPrice;
  final Money unitCost;
  final Money discount;
  final String? unitId;
  final String? unitName;
  final bool isService;

  String get currency => unitPrice.currency;

  Money get grossTotal => _multiply(unitPrice, quantity);

  Money get total => grossTotal - discount;

  Quantity get baseQuantity {
    final numerator = quantity.milliUnits * unitFactorToBase.milliUnits;
    final baseMilliUnits = (numerator + Quantity.scale ~/ 2) ~/ Quantity.scale;
    return Quantity.fromMilliUnits(baseMilliUnits);
  }

  Money get costTotal {
    if (isService) {
      return Money.zero(currency: currency);
    }
    return _multiply(unitCost, baseQuantity);
  }

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
