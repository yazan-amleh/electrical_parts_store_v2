import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/idempotency/idempotency_key.dart';

import '../../../../core/money/money.dart';
import '../../../../core/quantity/quantity.dart';
import '../../domain/entities/inventory_movement.dart';
import '../../domain/enums/inventory_movement_type.dart';

abstract final class InventoryMovementFirestoreMapper {
  static Map<String, dynamic> toMap(InventoryMovement movement) {
    return <String, dynamic>{
      'storeId': movement.storeId,
      'productId': movement.productId,
      'type': movement.type.name,
      'quantityDeltaMilliUnits': movement.quantityDelta.milliUnits,
      'unitCostMinorUnits': movement.unitCost.minorUnits,
      'currency': movement.unitCost.currency,
      'idempotencyKey': movement.idempotencyKey,
      'sourceType': movement.sourceType,
      'sourceId': movement.sourceId,
      'occurredAt': Timestamp.fromDate(movement.occurredAt),
    };
  }

  static InventoryMovement fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final typeName = data['type'] is String ? data['type'] as String : '';
    final movementType = InventoryMovementType.values.firstWhere(
      (type) => type.name == typeName,
      orElse: () => InventoryMovementType.adjustment,
    );
    final currency = _string(data['currency'], 'ILS');

    return InventoryMovement(
      id: snapshot.id,
      storeId: _string(data['storeId'], ''),
      productId: _string(data['productId'], ''),
      type: movementType,
      quantityDelta: Quantity.fromMilliUnits(
        _int(data['quantityDeltaMilliUnits']),
      ),
      unitCost: Money(
        minorUnits: _int(data['unitCostMinorUnits']),
        currency: currency,
      ),
      idempotencyKey: IdempotencyKey(
        _string(data['idempotencyKey'], snapshot.id),
      ),
      sourceType: _string(data['sourceType'], ''),
      sourceId: data['sourceId'] as String?,
      occurredAt: _date(data['occurredAt']) ?? DateTime.now().toUtc(),
    );
  }

  static DateTime? _date(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }

  static String _string(Object? value, String fallback) {
    return value is String && value.isNotEmpty ? value : fallback;
  }

  static int _int(Object? value, [int fallback = 0]) {
    return value is int
        ? value
        : value is num
            ? value.toInt()
            : fallback;
  }
}
