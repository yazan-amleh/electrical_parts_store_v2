import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/purchase.dart';
import '../entities/purchase_posting_plan.dart';
import '../entities/purchase_invoice.dart';
import '../entities/purchase_return.dart';

abstract interface class PurchaseRepository {
  Future<Result<PurchasePostingPlan>> postPurchase({
    required StoreContext context,
    required Purchase purchase,
    required PurchasePostingAccounts accounts,
  });

  Future<Result<List<PurchaseInvoiceSummary>>> getRecentPurchaseInvoices({
    required StoreContext context,
    int limit = 100,
  });

  Future<Result<PurchaseInvoiceDocument>> getPurchaseInvoiceDocument({
    required StoreContext context,
    required String purchaseId,
  });

  Future<Result<PurchaseReturnPostingResult>> postPurchaseReturn({
    required StoreContext context,
    required PurchaseReturn purchaseReturn,
    required PurchaseReturnPostingAccounts accounts,
  });
}
