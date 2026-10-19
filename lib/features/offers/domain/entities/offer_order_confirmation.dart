class OfferOrderConfirmation {
  const OfferOrderConfirmation({
    required this.orderId,
    required this.saleId,
    required this.journalEntryId,
  });

  final String orderId;
  final String saleId;
  final String journalEntryId;
}
