import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/idempotency/idempotency_key.dart';
import '../../../../core/money/money.dart';
import '../../../../core/quantity/quantity.dart';
import '../../domain/entities/inventory_movement.dart';
import '../../domain/enums/inventory_movement_type.dart';

abstract final class InventoryMovementFirestoreMapper {
  static InventoryMovement fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final currency = _string(data['currency'], 'ILS');
    final type = InventoryMovementType.values.firstWhere(
      (value) => value.name == _string(data['type'], ''),
      orElse: () => InventoryMovementType.adjustment,
    );

    return InventoryMovement(
      id: snapshot.id,
      storeId: _string(data['storeId'], ''),
      productId: _string(data['productId'], ''),
      type: type,
      quantityDelta: Quantity.fromMilliUnits(
        _int(data['quantityDeltaMilliUnits']),
      ),
      unitCost: Money(
        minorUnits: _int(data['unitCostMinorUnits']),
        currency: currency,
      ),
      totalCost: Money(
        minorUnits: _int(data['totalCostMinorUnits']),
        currency: currency,
      ),
      idempotencyKey: IdempotencyKey(
        _string(data['idempotencyKey'], snapshot.id),
      ),
      sourceType: _string(data['sourceType'], ''),
      sourceId: data['sourceId'] as String?,
      occurredAt: _date(data['occurredAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
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
