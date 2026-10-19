import '../../../../core/money/money.dart';
import '../../../../core/quantity/quantity.dart';

class PurchaseOrderLine {
  PurchaseOrderLine({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitFactorToBase,
    required this.unitCost,
    this.unitId,
    this.unitName,
    Quantity? receivedQuantity,
  }) : receivedQuantity = receivedQuantity ?? const Quantity.fromMilliUnits(0) {
    _ensureIdentifier(id, 'Purchase order line id');
    _ensureIdentifier(productId, 'Purchase order product id');
    if (productName.trim().isEmpty) {
      throw ArgumentError('Purchase order product name is required.');
    }
    if (quantity.milliUnits <= 0) {
      throw ArgumentError('Purchase order quantity must be positive.');
    }
    if (unitFactorToBase.milliUnits <= 0) {
      throw ArgumentError('Purchase order unit factor must be positive.');
    }
    if (unitCost.isNegative) {
      throw ArgumentError('Purchase order unit cost cannot be negative.');
    }
    if (this.receivedQuantity.isNegative ||
        this.receivedQuantity.milliUnits > quantity.milliUnits) {
      throw ArgumentError(
        'Received quantity must be between zero and ordered quantity.',
      );
    }
    if (unitId != null && unitId!.contains('/')) {
      throw ArgumentError('Purchase order unit id cannot contain a slash.');
    }
  }

  final String id;
  final String productId;
  final String productName;
  final Quantity quantity;
  final Quantity unitFactorToBase;
  final Money unitCost;
  final String? unitId;
  final String? unitName;
  final Quantity receivedQuantity;

  Quantity get remainingQuantity => quantity - receivedQuantity;

  Quantity get baseQuantity {
    final numerator = quantity.milliUnits * unitFactorToBase.milliUnits;
    final baseMilliUnits = (numerator + Quantity.scale ~/ 2) ~/ Quantity.scale;
    return Quantity.fromMilliUnits(baseMilliUnits);
  }

  Money get total {
    final numerator = unitCost.minorUnits * baseQuantity.milliUnits;
    return Money(
      minorUnits: (numerator + Quantity.scale ~/ 2) ~/ Quantity.scale,
      currency: unitCost.currency,
    );
  }

  PurchaseOrderLine copyWith({
    Quantity? receivedQuantity,
  }) {
    return PurchaseOrderLine(
      id: id,
      productId: productId,
      productName: productName,
      quantity: quantity,
      unitFactorToBase: unitFactorToBase,
      unitCost: unitCost,
      unitId: unitId,
      unitName: unitName,
      receivedQuantity: receivedQuantity ?? this.receivedQuantity,
    );
  }

  static void _ensureIdentifier(String value, String label) {
    if (value.trim().isEmpty || value.contains('/')) {
      throw ArgumentError('$label is invalid.');
    }
  }
}
