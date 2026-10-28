import '../../../../core/money/money.dart';

/// Read-only posted sale header. Never used to re-post a transaction.
class SalesInvoiceSummary {
  const SalesInvoiceSummary({
    required this.id,
    required this.storeId,
    required this.postedAt,
    required this.customerId,
    required this.paymentMethod,
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.cost,
    required this.journalEntryId,
    this.description,
    this.returnStatus,
    this.returnId,
    this.returnedAt,
  });

  final String id;
  final String storeId;
  final DateTime postedAt;
  final String? customerId;
  final String paymentMethod;
  final Money subtotal;
  final Money tax;
  final Money total;
  final Money cost;
  final String journalEntryId;
  final String? description;
  final String? returnStatus;
  final String? returnId;
  final DateTime? returnedAt;

  bool get isFullyReturned => returnStatus == 'full';
  bool get isPartiallyReturned => returnStatus == 'partial';
}

class SalesInvoiceReport {
  const SalesInvoiceReport({
    required this.invoices,
    required this.mayBeTruncated,
  });

  /// Only the invoices loaded for the requested date range.
  final List<SalesInvoiceSummary> invoices;
  final bool mayBeTruncated;
}

class SalesInvoiceLineSummary {
  const SalesInvoiceLineSummary({
    required this.id,
    required this.productId,
    required this.description,
    required this.quantityMilliUnits,
    required this.unitPrice,
    required this.discount,
    required this.total,
    required this.cost,
    this.returnedQuantityMilliUnits = 0,
    this.unitName,
    this.isService = false,
  });

  final String id;
  final String productId;
  final String description;
  final int quantityMilliUnits;
  final Money unitPrice;
  final Money discount;
  final Money total;
  final Money cost;
  final int returnedQuantityMilliUnits;
  final String? unitName;
  final bool isService;

  int get remainingQuantityMilliUnits =>
      quantityMilliUnits - returnedQuantityMilliUnits;

  bool get isFullyReturned =>
      remainingQuantityMilliUnits <= 0;
}

class SalesInvoiceDocument {
  const SalesInvoiceDocument({
    required this.invoice,
    required this.lines,
  });

  final SalesInvoiceSummary invoice;
  final List<SalesInvoiceLineSummary> lines;
}
