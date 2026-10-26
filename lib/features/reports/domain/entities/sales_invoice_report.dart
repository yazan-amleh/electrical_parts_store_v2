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
