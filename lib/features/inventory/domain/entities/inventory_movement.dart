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
    required IdempotencyKey idempotencyKey,
    this.sourceType = '',
    this.sourceId,
    DateTime? occurredAt,
  })  : idempotencyKey = idempotencyKey.value,
        occurredAt = (occurredAt ?? DateTime.now()).toUtc() {
    if (id.trim().isEmpty ||
        storeId.trim().isEmpty ||
        productId.trim().isEmpty) {
      throw ArgumentError('Inventory movement identity fields are required.');
    }
    if (quantityDelta.isZero) {
      throw ArgumentError('Inventory movement quantity cannot be zero.');
    }
    if (unitCost.isNegative) {
      throw ArgumentError('Inventory movement unit cost cannot be negative.');
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
  final String idempotencyKey;
  final String sourceType;
  final String? sourceId;
  final DateTime occurredAt;
}
