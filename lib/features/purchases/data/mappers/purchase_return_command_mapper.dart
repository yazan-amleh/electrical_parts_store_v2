import '../../domain/entities/purchase_return.dart';

abstract final class PurchaseReturnCommandMapper {
  static Map<String, dynamic> toRequest({
    required PurchaseReturn purchaseReturn,
    required PurchaseReturnPostingAccounts accounts,
  }) {
    return <String, dynamic>{
      'storeId': purchaseReturn.storeId,
      'purchaseReturn': <String, dynamic>{
        'id': purchaseReturn.id,
        'idempotencyKey': purchaseReturn.idempotencyKey.value,
        'originalPurchaseId': purchaseReturn.originalPurchaseId,
        'postedAt': purchaseReturn.postedAt.toIso8601String(),
        'reason': purchaseReturn.reason,
        if (purchaseReturn.lines != null)
          'lines': [
            for (final line in purchaseReturn.lines!)
              <String, dynamic>{
                'lineId': line.lineId,
                'quantityMilliUnits': line.quantityMilliUnits,
              },
          ],
      },
      'postingAccounts': <String, dynamic>{
        'settlementAccountId': accounts.settlementAccountId,
        'supplierPayableAccountId': accounts.supplierPayableAccountId,
        'inventoryAccountId': accounts.inventoryAccountId,
        'inputTaxAccountId': accounts.inputTaxAccountId,
        'purchaseReturnVarianceAccountId':
            accounts.purchaseReturnVarianceAccountId,
      },
    };
  }
}
