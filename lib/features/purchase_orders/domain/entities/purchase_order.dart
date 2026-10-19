import '../../../../core/money/money.dart';
import '../../../../core/tenancy/store_context.dart';
import '../enums/purchase_order_status.dart';
import 'purchase_order_line.dart';

class PurchaseOrder {
  PurchaseOrder({
    required this.id,
    required this.storeId,
    required this.orderNumber,
    required this.supplierId,
    required this.supplierName,
    required DateTime orderedAt,
    required List<PurchaseOrderLine> lines,
    required this.status,
    this.notes,
    this.receiptId,
    DateTime? completedAt,
  })  : orderedAt = orderedAt.toUtc(),
        lines = List.unmodifiable(lines),
        completedAt = completedAt?.toUtc() {
    _ensureIdentifier(id, 'Purchase order id');
    _ensureIdentifier(storeId, 'Purchase order store id');
    _ensureIdentifier(supplierId, 'Purchase order supplier id');
    if (orderNumber.trim().isEmpty) {
      throw ArgumentError('Purchase order number is required.');
    }
    if (supplierName.trim().isEmpty) {
      throw ArgumentError('Purchase order supplier name is required.');
    }
    if (this.lines.isEmpty) {
      throw ArgumentError('A purchase order needs at least one line.');
    }

    final lineIds = this.lines.map((line) => line.id).toSet();
    if (lineIds.length != this.lines.length) {
      throw ArgumentError('Purchase order line ids must be unique.');
    }

    final currency = this.lines.first.unitCost.currency;
    for (final line in this.lines) {
      if (line.unitCost.currency != currency) {
        throw ArgumentError('Purchase order lines must use one currency.');
      }
    }

    if (receiptId != null && receiptId!.contains('/')) {
      throw ArgumentError('Purchase order receipt id cannot contain a slash.');
    }
  }

  final String id;
  final String storeId;
  final String orderNumber;
  final String supplierId;
  final String supplierName;
  final DateTime orderedAt;
  final List<PurchaseOrderLine> lines;
  final PurchaseOrderStatus status;
  final String? notes;
  final String? receiptId;
  final DateTime? completedAt;

  String get currency => lines.first.unitCost.currency;

  Money get total {
    return lines.fold(
      Money.zero(currency: currency),
      (sum, line) => sum + line.total,
    );
  }

  bool get canReceive => status.isOpen;
  bool get canCancel => status.isOpen;

  StoreContext contextFor(String userId) {
    return StoreContext(storeId: storeId, userId: userId);
  }

  static void _ensureIdentifier(String value, String label) {
    if (value.trim().isEmpty || value.contains('/')) {
      throw ArgumentError('$label is invalid.');
    }
  }
}
