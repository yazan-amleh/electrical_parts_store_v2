import '../../domain/entities/purchase.dart';
import '../../domain/entities/purchase_line.dart';
import '../../domain/entities/purchase_posting_plan.dart';

abstract final class PurchaseCommandMapper {
  static Map<String, dynamic> toRequest({
    required Purchase purchase,
    required PurchasePostingAccounts accounts,
  }) {
    return <String, dynamic>{
      'storeId': purchase.storeId,
      'purchase': <String, dynamic>{
        'id': purchase.id,
        'idempotencyKey': purchase.idempotencyKey.value,
        'postedAt': purchase.postedAt.toUtc().toIso8601String(),
        'paymentMethod': purchase.paymentMethod.name,
        'supplierId': purchase.supplierId,
        'description': purchase.description,
        'currency': purchase.currency,
        'taxMinorUnits': purchase.tax.minorUnits,
        'lines': purchase.lines.map(_lineToMap).toList(growable: false),
      },
      'postingAccounts': <String, dynamic>{
        'settlementAccountId': accounts.settlementAccountId,
        'inventoryAccountId': accounts.inventoryAccountId,
        'supplierPayableAccountId': accounts.supplierPayableAccountId,
        'inputTaxAccountId': accounts.inputTaxAccountId,
      },
    };
  }

  static Map<String, dynamic> _lineToMap(PurchaseLine line) {
    return <String, dynamic>{
      'id': line.id,
      'productId': line.productId,
      'description': line.description,
      'quantityMilliUnits': line.quantity.milliUnits,
      'unitFactorToBaseMilliUnits': line.unitFactorToBase.milliUnits,
      'unitCostMinorUnits': line.unitCost.minorUnits,
      'discountMinorUnits': line.discount.minorUnits,
      'unitId': line.unitId,
      'unitName': line.unitName,
    };
  }
}
