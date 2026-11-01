import '../../../../core/idempotency/idempotency_key.dart';

class PurchaseReturnLineRequest {
  PurchaseReturnLineRequest({
    required this.lineId,
    required this.quantityMilliUnits,
  }) {
    if (lineId.trim().isEmpty || lineId.contains('/')) {
      throw ArgumentError('Purchase return line id is invalid.');
    }
    if (quantityMilliUnits <= 0) {
      throw ArgumentError('Purchase return quantity must be positive.');
    }
  }

  final String lineId;
  final int quantityMilliUnits;
}

class PurchaseReturn {
  PurchaseReturn({
    required this.id,
    required this.storeId,
    required this.idempotencyKey,
    required this.originalPurchaseId,
    required DateTime postedAt,
    this.reason,
    List<PurchaseReturnLineRequest>? lines,
  })  : postedAt = postedAt.toUtc(),
        lines = lines == null ? null : List.unmodifiable(lines) {
    _safeId(id, 'Purchase return id');
    _safeId(storeId, 'Store id');
    _safeId(originalPurchaseId, 'Original purchase id');
    if (idempotencyKey.value.contains('/')) {
      throw ArgumentError(
        'Purchase return idempotency key cannot contain a slash.',
      );
    }
    if (this.lines != null) {
      if (this.lines!.isEmpty || this.lines!.length > 100) {
        throw ArgumentError('Partial purchase return requires 1 to 100 lines.');
      }
      final ids = this.lines!.map((line) => line.lineId).toSet();
      if (ids.length != this.lines!.length) {
        throw ArgumentError('Purchase return line ids must be unique.');
      }
    }
  }

  final String id;
  final String storeId;
  final IdempotencyKey idempotencyKey;
  final String originalPurchaseId;
  final DateTime postedAt;
  final String? reason;
  final List<PurchaseReturnLineRequest>? lines;

  bool get isPartialRequest => lines != null;

  static void _safeId(String value, String label) {
    if (value.trim().isEmpty) {
      throw ArgumentError('$label is required.');
    }
    if (value.contains('/')) {
      throw ArgumentError('$label cannot contain a slash.');
    }
  }
}

class PurchaseReturnPostingAccounts {
  const PurchaseReturnPostingAccounts({
    this.settlementAccountId,
    this.supplierPayableAccountId,
    required this.inventoryAccountId,
    this.inputTaxAccountId,
    required this.purchaseReturnVarianceAccountId,
  });

  final String? settlementAccountId;
  final String? supplierPayableAccountId;
  final String inventoryAccountId;
  final String? inputTaxAccountId;
  final String purchaseReturnVarianceAccountId;
}

class PurchaseReturnPostingResult {
  const PurchaseReturnPostingResult({
    required this.returnId,
    required this.originalPurchaseId,
    required this.journalEntryId,
    required this.alreadyReturned,
    required this.inventoryCarryingValueMinorUnits,
    required this.valuationVarianceMinorUnits,
    this.returnStatus,
  });

  final String returnId;
  final String originalPurchaseId;
  final String journalEntryId;
  final bool alreadyReturned;
  final int inventoryCarryingValueMinorUnits;
  final int valuationVarianceMinorUnits;
  final String? returnStatus;
}
