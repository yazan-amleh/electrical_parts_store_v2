import '../../domain/entities/inventory_movement.dart';

abstract final class InventoryMovementCommandMapper {
  static Map<String, dynamic> toRequest(InventoryMovement movement) {
    return <String, dynamic>{
      'storeId': movement.storeId,
      'movement': <String, dynamic>{
        'id': movement.id,
        'idempotencyKey': movement.idempotencyKey,
        'productId': movement.productId,
        'type': movement.type.name,
        'quantityDeltaMilliUnits': movement.quantityDelta.milliUnits,
        'unitCostMinorUnits': movement.unitCost.minorUnits,
        'totalCostMinorUnits': movement.totalCost.minorUnits,
        'currency': movement.unitCost.currency,
        'sourceType': movement.sourceType,
        'sourceId': movement.sourceId,
        'description': movement.description,
        'occurredAt': movement.occurredAt.toUtc().toIso8601String(),
      },
    };
  }
}
