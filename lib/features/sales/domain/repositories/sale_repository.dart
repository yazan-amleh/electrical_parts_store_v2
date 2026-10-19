import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/sale.dart';
import '../entities/sale_posting_plan.dart';

abstract interface class SaleRepository {
  Future<Result<SalePostingPlan>> postSale({
    required StoreContext context,
    required Sale sale,
    required SalePostingAccounts accounts,
  });
}
