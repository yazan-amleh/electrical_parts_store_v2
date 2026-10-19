class PurchaseOrderReceipt {
  const PurchaseOrderReceipt({
    required this.orderId,
    required this.purchaseId,
    required this.journalEntryId,
  });

  final String orderId;
  final String purchaseId;
  final String journalEntryId;
}
