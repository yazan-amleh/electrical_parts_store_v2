import '../../../../core/idempotency/idempotency_key.dart';
import '../../../sales/domain/entities/sale_posting_plan.dart';
import '../../../sales/domain/enums/sale_payment_method.dart';

class OfferOrderConfirmationRequest {
  OfferOrderConfirmationRequest({
    required this.orderId,
    required this.idempotencyKey,
    required DateTime postedAt,
    required this.paymentMethod,
    required this.accounts,
  }) : postedAt = postedAt.toUtc() {
    if (orderId.trim().isEmpty || orderId.contains('/')) {
      throw ArgumentError('Offer order id is invalid.');
    }
    if (idempotencyKey.value.contains('/')) {
      throw ArgumentError(
        'Offer confirmation idempotency key cannot contain a slash.',
      );
    }
  }

  final String orderId;
  final IdempotencyKey idempotencyKey;
  final DateTime postedAt;
  final SalePaymentMethod paymentMethod;
  final SalePostingAccounts accounts;
}

class OfferOrderConfirmation {
  const OfferOrderConfirmation({
    required this.orderId,
    required this.saleId,
    required this.journalEntryId,
    required this.alreadyConfirmed,
  });

  final String orderId;
  final String saleId;
  final String journalEntryId;
  final bool alreadyConfirmed;
}
