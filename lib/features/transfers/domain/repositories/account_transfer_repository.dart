import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/account_transfer.dart';
import '../entities/account_transfer_posting_plan.dart';

abstract interface class AccountTransferRepository {
  Future<Result<AccountTransferPostingPlan>> postTransfer({
    required StoreContext context,
    required AccountTransfer transfer,
  });
}
