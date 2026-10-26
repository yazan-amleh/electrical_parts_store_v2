import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/party_payment.dart';
import '../entities/party_payment_posting_plan.dart';
import '../entities/voucher_draft.dart';

abstract interface class VoucherDraftRepository {
  Future<Result<String>> saveDraft({
    required StoreContext context,
    required PartyPayment payment,
    required PartyPaymentPostingAccounts accounts,
  });

  Future<Result<void>> submit({
    required StoreContext context,
    required String draftId,
  });

  Future<Result<void>> approve({
    required StoreContext context,
    required String draftId,
  });

  Future<Result<void>> reject({
    required StoreContext context,
    required String draftId,
    required String reason,
  });

  /// The most recent 100 drafts; not a complete financial archive.
  Future<Result<List<VoucherDraft>>> getRecentDrafts({
    required StoreContext context,
  });
}
