import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/purchase.dart';
import '../entities/purchase_posting_plan.dart';

abstract interface class PurchaseRepository {
  Future<Result<PurchasePostingPlan>> postPurchase({
    required StoreContext context,
    required Purchase purchase,
    required PurchasePostingAccounts accounts,
  });
}
