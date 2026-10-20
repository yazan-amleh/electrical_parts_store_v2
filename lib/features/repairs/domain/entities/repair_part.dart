import '../../../../core/money/money.dart';
import '../../../../core/quantity/quantity.dart';

class RepairPart {
  RepairPart({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.unitCost,
    this.source = 'products',
  }) {
    _ensureIdentifier(id, 'Repair part id');
    _ensureIdentifier(productId, 'Repair product id');
    if (productName.trim().isEmpty) {
      throw ArgumentError('Repair product name is required.');
    }
    if (quantity.milliUnits <= 0) {
      throw ArgumentError('Repair part quantity must be positive.');
    }
    if (unitPrice.isNegative || unitCost.isNegative) {
      throw ArgumentError('Repair part prices cannot be negative.');
    }
    if (unitPrice.currency != unitCost.currency) {
      throw ArgumentError('Repair part prices must use one currency.');
    }
  }

  final String id;
  final String productId;
  final String productName;
  final Quantity quantity;
  final Money unitPrice;
  final Money unitCost;
  final String source;

  Money get totalPrice => _multiply(unitPrice, quantity);
  Money get totalCost => _multiply(unitCost, quantity);

  static Money _multiply(Money amount, Quantity quantity) {
    final numerator = amount.minorUnits * quantity.milliUnits;
    final minorUnits = (numerator + Quantity.scale ~/ 2) ~/ Quantity.scale;
    return Money(minorUnits: minorUnits, currency: amount.currency);
  }

  static void _ensureIdentifier(String value, String label) {
    if (value.trim().isEmpty || value.contains('/')) {
      throw ArgumentError('$label is invalid.');
    }
  }
}
