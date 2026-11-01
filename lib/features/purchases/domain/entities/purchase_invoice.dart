import '../../../../core/money/money.dart';

class PurchaseInvoiceSummary {
  const PurchaseInvoiceSummary({
    required this.id,
    required this.storeId,
    required this.postedAt,
    required this.paymentMethod,
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.journalEntryId,
    this.supplierId,
    this.description,
    this.returnStatus,
    this.returnId,
    this.returnedAt,
  });

  final String id;
  final String storeId;
  final DateTime postedAt;
  final String paymentMethod;
  final Money subtotal;
  final Money tax;
  final Money total;
  final String journalEntryId;
  final String? supplierId;
  final String? description;
  final String? returnStatus;
  final String? returnId;
  final DateTime? returnedAt;

  bool get isFullyReturned => returnStatus == 'full';
  bool get isPartiallyReturned => returnStatus == 'partial';
}

class PurchaseInvoiceLineSummary {
  const PurchaseInvoiceLineSummary({
    required this.id,
    required this.productId,
    required this.description,
    required this.quantityMilliUnits,
    required this.baseQuantityMilliUnits,
    required this.unitCost,
    required this.discount,
    required this.total,
    this.returnedQuantityMilliUnits = 0,
    this.unitName,
  });

  final String id;
  final String productId;
  final String description;
  final int quantityMilliUnits;
  final int baseQuantityMilliUnits;
  final Money unitCost;
  final Money discount;
  final Money total;
  final int returnedQuantityMilliUnits;
  final String? unitName;

  int get remainingQuantityMilliUnits =>
      quantityMilliUnits - returnedQuantityMilliUnits;

  bool get isFullyReturned => remainingQuantityMilliUnits <= 0;
}

class PurchaseInvoiceDocument {
  const PurchaseInvoiceDocument({
    required this.invoice,
    required this.lines,
  });

  final PurchaseInvoiceSummary invoice;
  final List<PurchaseInvoiceLineSummary> lines;
}
