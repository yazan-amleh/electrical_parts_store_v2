import '../../../purchases/domain/entities/purchase_posting_plan.dart';
import '../../../purchases/domain/enums/purchase_payment_method.dart';
import '../../domain/entities/purchase_order.dart';
import '../../domain/entities/purchase_order_receipt.dart';
import '../../domain/entities/purchase_order_line.dart';

abstract final class PurchaseOrderCommandMapper {
  static Map<String, dynamic> createRequest(PurchaseOrder order) {
    return <String, dynamic>{
      'storeId': order.storeId,
      'order': <String, dynamic>{
        'id': order.id,
        'orderNumber': order.orderNumber,
        'supplierId': order.supplierId,
        'supplierName': order.supplierName,
        'currency': order.currency,
        'orderedAt': order.orderedAt.toUtc().toIso8601String(),
        'notes': order.notes,
        'lines': order.lines.map(_lineToMap).toList(growable: false),
      },
    };
  }

  static Map<String, dynamic> cancelRequest({
    required String storeId,
    required String orderId,
  }) {
    return <String, dynamic>{'storeId': storeId, 'orderId': orderId};
  }

  static Map<String, dynamic> receiveRequest({
    required PurchaseOrder order,
    required PurchaseOrderReceiptRequest receipt,
    required PurchasePaymentMethod paymentMethod,
    required PurchasePostingAccounts accounts,
    required int taxMinorUnits,
  }) {
    return <String, dynamic>{
      'storeId': order.storeId,
      'orderId': order.id,
      'receiptId': receipt.receiptId,
      'idempotencyKey': receipt.idempotencyKey.value,
      'postedAt': receipt.postedAt.toIso8601String(),
      'paymentMethod': paymentMethod.name,
      'taxMinorUnits': taxMinorUnits,
      'currency': order.currency,
      if (receipt.lines != null)
        'lines': [
          for (final line in receipt.lines!)
            <String, dynamic>{
              'lineId': line.lineId,
              'quantityMilliUnits': line.quantityMilliUnits,
            },
        ],
      'postingAccounts': <String, dynamic>{
        'settlementAccountId': accounts.settlementAccountId,
        'inventoryAccountId': accounts.inventoryAccountId,
        'supplierPayableAccountId': accounts.supplierPayableAccountId,
        'inputTaxAccountId': accounts.inputTaxAccountId,
      },
    };
  }

  static Map<String, dynamic> _lineToMap(PurchaseOrderLine line) {
    return <String, dynamic>{
      'id': line.id,
      'productId': line.productId,
      'productName': line.productName,
      'quantityMilliUnits': line.quantity.milliUnits,
      'unitFactorToBaseMilliUnits': line.unitFactorToBase.milliUnits,
      'unitCostMinorUnits': line.unitCost.minorUnits,
      'currency': line.unitCost.currency,
      'unitId': line.unitId,
      'unitName': line.unitName,
    };
  }
}
