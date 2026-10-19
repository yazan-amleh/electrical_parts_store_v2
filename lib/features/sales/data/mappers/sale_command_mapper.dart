import '../../domain/entities/sale.dart';
import '../../domain/entities/sale_posting_plan.dart';

abstract final class SaleCommandMapper {
  static Map<String, dynamic> toRequest({
    required Sale sale,
    required SalePostingAccounts accounts,
  }) {
    return <String, dynamic>{
      'storeId': sale.storeId,
      'sale': <String, dynamic>{
        'id': sale.id,
        'idempotencyKey': sale.idempotencyKey.value,
        'postedAt': sale.postedAt.toUtc().toIso8601String(),
        'paymentMethod': sale.paymentMethod.name,
        'customerId': sale.customerId,
        'description': sale.description,
        'currency': sale.currency,
        'taxMinorUnits': sale.tax.minorUnits,
        'lines': sale.lines.map(_lineToMap).toList(growable: false),
      },
      'postingAccounts': <String, dynamic>{
        'settlementAccountId': accounts.settlementAccountId,
        'salesAccountId': accounts.salesAccountId,
        'inventoryAccountId': accounts.inventoryAccountId,
        'costOfSalesAccountId': accounts.costOfSalesAccountId,
        'taxAccountId': accounts.taxAccountId,
      },
    };
  }

  static Map<String, dynamic> _lineToMap(line) {
    return <String, dynamic>{
      'id': line.id,
      'productId': line.productId,
      'description': line.description,
      'quantityMilliUnits': line.quantity.milliUnits,
      'unitFactorToBaseMilliUnits': line.unitFactorToBase.milliUnits,
      'unitPriceMinorUnits': line.unitPrice.minorUnits,
      'unitCostMinorUnits': line.unitCost.minorUnits,
      'discountMinorUnits': line.discount.minorUnits,
      'unitId': line.unitId,
      'unitName': line.unitName,
      'isService': line.isService,
    };
  }
}
