import '../../domain/entities/party_payment.dart';
import '../../domain/entities/party_payment_posting_plan.dart';

abstract final class PartyPaymentCommandMapper {
  static Map<String, dynamic> toRequest({
    required PartyPayment payment,
    required PartyPaymentPostingAccounts accounts,
  }) {
    return <String, dynamic>{
      'storeId': payment.storeId,
      'payment': <String, dynamic>{
        'id': payment.id,
        'idempotencyKey': payment.idempotencyKey.value,
        'postedAt': payment.postedAt.toUtc().toIso8601String(),
        'partyType': payment.partyType.name,
        'partyId': payment.partyId,
        'paymentMethod': payment.paymentMethod.name,
        'amountMinorUnits': payment.amount.minorUnits,
        'currency': payment.amount.currency,
        'description': payment.description,
      },
      'postingAccounts': <String, dynamic>{
        'settlementAccountId': accounts.settlementAccountId,
        'partyAccountId': accounts.partyAccountId,
      },
    };
  }
}
