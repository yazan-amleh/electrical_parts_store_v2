import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/party_payment.dart';
import '../entities/party_payment_posting_plan.dart';

abstract interface class PartyPaymentRepository {
  Future<Result<PartyPaymentPostingPlan>> postPartyPayment({
    required StoreContext context,
    required PartyPayment payment,
    required PartyPaymentPostingAccounts accounts,
  });
}
