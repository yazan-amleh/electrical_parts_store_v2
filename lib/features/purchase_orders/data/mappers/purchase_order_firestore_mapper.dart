import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/money/money.dart';
import '../../../../core/quantity/quantity.dart';
import '../../domain/entities/purchase_order.dart';
import '../../domain/entities/purchase_order_line.dart';
import '../../domain/enums/purchase_order_status.dart';

abstract final class PurchaseOrderFirestoreMapper {
  static PurchaseOrder fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final currency = _string(data['currency'], 'ILS');
    final rawLines = data['lines'] is List<Object?>
        ? data['lines'] as List<Object?>
        : const <Object?>[];
    final lines = rawLines
        .whereType<Map<String, dynamic>>()
        .map(
          (raw) => _lineFromMap(
            raw,
            productIdFallback: snapshot.id,
            currency: currency,
          ),
        )
        .toList(growable: false);

    return PurchaseOrder(
      id: snapshot.id,
      storeId: _string(data['storeId']),
      orderNumber: _string(data['orderNumber'], snapshot.id),
      supplierId: _string(data['supplierId']),
      supplierName: _string(data['supplierName'], 'مورد غير معروف'),
      orderedAt:
          _date(data['orderedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      lines: lines,
      status: purchaseOrderStatusFromName(data['status'] as String?),
      notes: data['notes'] as String?,
      receiptId: data['receiptId'] as String?,
      completedAt: _date(data['completedAt']),
    );
  }

  static Map<String, dynamic> toMap(PurchaseOrder order) {
    return <String, dynamic>{
      'storeId': order.storeId,
      'orderNumber': order.orderNumber,
      'supplierId': order.supplierId,
      'supplierName': order.supplierName,
      'currency': order.currency,
      'orderedAt': Timestamp.fromDate(order.orderedAt),
      'status': order.status.name,
      'notes': order.notes,
      'receiptId': order.receiptId,
      'completedAt': order.completedAt == null
          ? null
          : Timestamp.fromDate(order.completedAt!),
      'totalMinorUnits': order.total.minorUnits,
      'lines': order.lines.map(_lineToMap).toList(growable: false),
    };
  }

  static PurchaseOrderLine _lineFromMap(
    Map<String, dynamic> data, {
    required String productIdFallback,
    required String currency,
  }) {
    final productId = _string(data['productId'], productIdFallback);
    final lineCurrency = _string(data['currency'], currency);
    return PurchaseOrderLine(
      id: _string(data['id'], '$productId-line'),
      productId: productId,
      productName: _string(data['productName'], productId),
      quantity: Quantity.fromMilliUnits(_int(data['quantityMilliUnits'])),
      unitFactorToBase: Quantity.fromMilliUnits(
        _int(data['unitFactorToBaseMilliUnits'], Quantity.scale),
      ),
      unitCost: Money(
        minorUnits: _int(data['unitCostMinorUnits']),
        currency: lineCurrency,
      ),
      unitId: data['unitId'] as String?,
      unitName: data['unitName'] as String?,
      receivedQuantity: Quantity.fromMilliUnits(
        _int(data['receivedQuantityMilliUnits']),
      ),
    );
  }

  static Map<String, dynamic> _lineToMap(PurchaseOrderLine line) {
    return <String, dynamic>{
      'id': line.id,
      'productId': line.productId,
      'productName': line.productName,
      'quantityMilliUnits': line.quantity.milliUnits,
      'unitFactorToBaseMilliUnits': line.unitFactorToBase.milliUnits,
      'unitCostMinorUnits': line.unitCost.minorUnits,
      'currency': line.unitCost.currency,
      'unitId': line.unitId,
      'unitName': line.unitName,
      'receivedQuantityMilliUnits': line.receivedQuantity.milliUnits,
      'totalMinorUnits': line.total.minorUnits,
    };
  }

  static String _string(Object? value, [String fallback = '']) {
    return value is String && value.trim().isNotEmpty ? value : fallback;
  }

  static int _int(Object? value, [int fallback = 0]) {
    return value is int
        ? value
        : value is num
        ? value.toInt()
        : fallback;
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
}
