import '../../../../core/idempotency/idempotency_key.dart';
import '../../../../core/money/money.dart';
import '../../../../core/quantity/quantity.dart';
import '../enums/inventory_movement_type.dart';

class InventoryMovement {
  InventoryMovement({
    required this.id,
    required this.storeId,
    required this.productId,
    required this.type,
    required this.quantityDelta,
    required this.unitCost,
    Money? totalCost,
    required IdempotencyKey idempotencyKey,
    this.sourceType = '',
    this.sourceId,
    this.description = '',
    DateTime? occurredAt,
  }) : totalCost = totalCost ?? _defaultTotalCost(quantityDelta, unitCost),
       idempotencyKey = idempotencyKey.value,
       occurredAt = (occurredAt ?? DateTime.now()).toUtc() {
    if (id.trim().isEmpty ||
        storeId.trim().isEmpty ||
        productId.trim().isEmpty) {
      throw ArgumentError('Inventory movement identity fields are required.');
    }
    if (quantityDelta.isZero) {
      throw ArgumentError('Inventory movement quantity cannot be zero.');
    }
    if (unitCost.isNegative || this.totalCost.isNegative) {
      throw ArgumentError('Inventory movement costs cannot be negative.');
    }
    if (this.totalCost.currency != unitCost.currency) {
      throw ArgumentError('Inventory movement costs must use one currency.');
    }
    if (this.idempotencyKey.trim().isEmpty) {
      throw ArgumentError('Inventory movement idempotency key is required.');
    }
  }

  final String id;
  final String storeId;
  final String productId;
  final InventoryMovementType type;
  final Quantity quantityDelta;
  final Money unitCost;
  final Money totalCost;
  final String idempotencyKey;
  final String sourceType;
  final String? sourceId;
  final String description;
  final DateTime occurredAt;

  static Money _defaultTotalCost(Quantity quantity, Money unitCost) {
    final numerator = quantity.milliUnits.abs() * unitCost.minorUnits;
    final minorUnits = (numerator + Quantity.scale ~/ 2) ~/ Quantity.scale;
    return Money(minorUnits: minorUnits, currency: unitCost.currency);
  }
}
