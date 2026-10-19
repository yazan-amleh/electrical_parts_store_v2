import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../purchases/domain/entities/purchase_posting_plan.dart';
import '../../../purchases/domain/enums/purchase_payment_method.dart';
import '../entities/purchase_order.dart';
import '../entities/purchase_order_receipt.dart';

abstract interface class PurchaseOrderRepository {
  Future<Result<List<PurchaseOrder>>> getPurchaseOrders({
    required StoreContext context,
  });

  Future<Result<PurchaseOrder>> createPurchaseOrder({
    required StoreContext context,
    required PurchaseOrder order,
  });

  Future<Result<void>> cancelPurchaseOrder({
    required StoreContext context,
    required String orderId,
  });

  Future<Result<PurchaseOrderReceipt>> receivePurchaseOrder({
    required StoreContext context,
    required PurchaseOrder order,
    required PurchasePaymentMethod paymentMethod,
    required PurchasePostingAccounts accounts,
    required int taxMinorUnits,
  });
}
