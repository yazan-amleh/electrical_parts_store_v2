import '../../../../core/idempotency/idempotency_key.dart';

class SaleReturnLineRequest {
  const SaleReturnLineRequest({
    required this.lineId,
    required this.quantityMilliUnits,
  }) {
    if (lineId.trim().isEmpty || lineId.contains('/')) {
      throw ArgumentError('Sale return line id is invalid.');
    }
    if (quantityMilliUnits <= 0) {
      throw ArgumentError('Sale return quantity must be positive.');
    }
  }

  final String lineId;
  final int quantityMilliUnits;
}

class SaleReturn {
  SaleReturn({
    required this.id,
    required this.storeId,
    required this.idempotencyKey,
    required this.originalSaleId,
    required DateTime postedAt,
    this.reason,
    List<SaleReturnLineRequest>? lines,
  })  : postedAt = postedAt.toUtc(),
        lines = lines == null ? null : List.unmodifiable(lines) {
    _safeId(id, 'Sale return id');
    _safeId(storeId, 'Store id');
    _safeId(originalSaleId, 'Original sale id');
    if (idempotencyKey.value.contains('/')) {
      throw ArgumentError(
        'Sale return idempotency key cannot contain a slash.',
      );
    }
    if (this.lines != null) {
      if (this.lines!.isEmpty || this.lines!.length > 100) {
        throw ArgumentError('Partial sale return requires 1 to 100 lines.');
      }
      final ids = this.lines!.map((line) => line.lineId).toSet();
      if (ids.length != this.lines!.length) {
        throw ArgumentError('Sale return line ids must be unique.');
      }
    }
  }

  final String id;
  final String storeId;
  final IdempotencyKey idempotencyKey;
  final String originalSaleId;
  final DateTime postedAt;
  final String? reason;

  /// Null means return every remaining quantity from the original invoice.
  /// A non-empty list requests a partial return for the specified quantities.
  final List<SaleReturnLineRequest>? lines;

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

class SaleReturnPostingAccounts {
  const SaleReturnPostingAccounts({
    this.settlementAccountId,
    this.customerReceivableAccountId,
    required this.salesReturnsAccountId,
    required this.inventoryAccountId,
    required this.costOfSalesAccountId,
    this.taxAccountId,
  });

  final String? settlementAccountId;
  final String? customerReceivableAccountId;
  final String salesReturnsAccountId;
  final String inventoryAccountId;
  final String costOfSalesAccountId;
  final String? taxAccountId;
}

class SaleReturnPostingResult {
  const SaleReturnPostingResult({
    required this.returnId,
    required this.originalSaleId,
    required this.journalEntryId,
    required this.alreadyReturned,
    this.returnStatus,
  });

  final String returnId;
  final String originalSaleId;
  final String journalEntryId;
  final bool alreadyReturned;
  final String? returnStatus;
}
