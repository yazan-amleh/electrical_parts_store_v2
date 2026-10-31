import '../../../../core/idempotency/idempotency_key.dart';

class PurchaseOrderReceiptLine {
  PurchaseOrderReceiptLine({
    required this.lineId,
    required this.quantityMilliUnits,
  }) {
    if (lineId.trim().isEmpty || lineId.contains('/')) {
      throw ArgumentError('Purchase order receipt line id is invalid.');
    }
    if (quantityMilliUnits <= 0) {
      throw ArgumentError('Receipt quantity must be positive.');
    }
  }

  final String lineId;
  final int quantityMilliUnits;
}

class PurchaseOrderReceiptRequest {
  PurchaseOrderReceiptRequest({
    required this.receiptId,
    required this.idempotencyKey,
    required DateTime postedAt,
    List<PurchaseOrderReceiptLine>? lines,
  })  : postedAt = postedAt.toUtc(),
        lines = lines == null ? null : List.unmodifiable(lines) {
    if (receiptId.trim().isEmpty || receiptId.contains('/')) {
      throw ArgumentError('Purchase order receipt id is invalid.');
    }
    if (idempotencyKey.value.contains('/')) {
      throw ArgumentError(
        'Purchase order receipt idempotency key cannot contain a slash.',
      );
    }
    if (this.lines != null) {
      if (this.lines!.isEmpty || this.lines!.length > 100) {
        throw ArgumentError('Receipt must contain between 1 and 100 lines.');
      }
      final ids = this.lines!.map((line) => line.lineId).toSet();
      if (ids.length != this.lines!.length) {
        throw ArgumentError('Receipt line ids must be unique.');
      }
    }
  }

  final String receiptId;
  final IdempotencyKey idempotencyKey;
  final DateTime postedAt;

  /// Null means receive every currently remaining quantity.
  final List<PurchaseOrderReceiptLine>? lines;
}

class PurchaseOrderReceipt {
  const PurchaseOrderReceipt({
    required this.orderId,
    required this.purchaseId,
    required this.journalEntryId,
    required this.completed,
    required this.orderStatus,
  });

  final String orderId;
  final String purchaseId;
  final String journalEntryId;
  final bool completed;
  final String orderStatus;
}
