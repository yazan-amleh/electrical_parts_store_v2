import '../../domain/entities/sale_return.dart';

abstract final class SaleReturnCommandMapper {
  static Map<String, dynamic> toRequest({
    required SaleReturn saleReturn,
    required SaleReturnPostingAccounts accounts,
  }) {
    return {
      'storeId': saleReturn.storeId,
      'saleReturn': {
        'id': saleReturn.id,
        'idempotencyKey': saleReturn.idempotencyKey.value,
        'originalSaleId': saleReturn.originalSaleId,
        'postedAt': saleReturn.postedAt.toIso8601String(),
        'reason': saleReturn.reason,
        if (saleReturn.lines != null)
          'lines': [
            for (final line in saleReturn.lines!)
              {
                'lineId': line.lineId,
                'quantityMilliUnits': line.quantityMilliUnits,
              },
          ],
      },
      'postingAccounts': {
        'settlementAccountId': accounts.settlementAccountId,
        'customerReceivableAccountId': accounts.customerReceivableAccountId,
        'salesReturnsAccountId': accounts.salesReturnsAccountId,
        'inventoryAccountId': accounts.inventoryAccountId,
        'costOfSalesAccountId': accounts.costOfSalesAccountId,
        'taxAccountId': accounts.taxAccountId,
      },
    };
  }
}
