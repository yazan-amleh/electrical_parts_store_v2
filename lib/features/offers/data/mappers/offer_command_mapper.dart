import '../../../sales/domain/entities/sale_posting_plan.dart';
import '../../../sales/domain/enums/sale_payment_method.dart';
import '../../domain/entities/offer.dart';
import '../../domain/entities/offer_line.dart';
import '../../domain/entities/offer_order.dart';
import '../../domain/entities/offer_order_confirmation.dart';

abstract final class OfferCommandMapper {
  static Map<String, dynamic> createOfferRequest(Offer offer) {
    return <String, dynamic>{
      'storeId': offer.storeId,
      'offer': _offerMap(offer),
      'idempotencyKey': offer.id,
    };
  }

  static Map<String, dynamic> updateOfferRequest(Offer offer) {
    return <String, dynamic>{
      'storeId': offer.storeId,
      'offerId': offer.id,
      'offer': _offerMap(offer),
    };
  }

  static Map<String, dynamic> setActiveRequest({
    required String storeId,
    required String offerId,
    required bool isActive,
  }) {
    return <String, dynamic>{
      'storeId': storeId,
      'offerId': offerId,
      'isActive': isActive,
    };
  }

  static Map<String, dynamic> archiveRequest({
    required String storeId,
    required String offerId,
  }) {
    return <String, dynamic>{'storeId': storeId, 'offerId': offerId};
  }

  static Map<String, dynamic> createOrderRequest(OfferOrder order) {
    return <String, dynamic>{
      'storeId': order.storeId,
      'order': <String, dynamic>{
        'id': order.id,
        'orderNumber': order.orderNumber,
        'offerId': order.offerId,
        'customerId': order.customerId,
        'idempotencyKey': order.idempotencyKey.value,
        'createdAt': order.createdAt.toUtc().toIso8601String(),
      },
    };
  }

  static Map<String, dynamic> confirmOrderRequest({
    required OfferOrder order,
    required OfferOrderConfirmationRequest confirmation,
  }) {
    return <String, dynamic>{
      'storeId': order.storeId,
      'orderId': order.id,
      'idempotencyKey': confirmation.idempotencyKey.value,
      'postedAt': confirmation.postedAt.toIso8601String(),
      'paymentMethod': confirmation.paymentMethod.name,
      'postingAccounts': <String, dynamic>{
        'settlementAccountId': confirmation.accounts.settlementAccountId,
        'customerReceivableAccountId':
            confirmation.accounts.customerReceivableAccountId,
        'salesAccountId': confirmation.accounts.salesAccountId,
        'inventoryAccountId': confirmation.accounts.inventoryAccountId,
        'costOfSalesAccountId': confirmation.accounts.costOfSalesAccountId,
        'taxAccountId': confirmation.accounts.taxAccountId,
      },
    };
  }

  static Map<String, dynamic> cancelOrderRequest({
    required String storeId,
    required String orderId,
  }) {
    return <String, dynamic>{'storeId': storeId, 'orderId': orderId};
  }

  static Map<String, dynamic> _offerMap(Offer offer) {
    return <String, dynamic>{
      'id': offer.id,
      'offerNumber': offer.offerNumber,
      'name': offer.name,
      'description': offer.description,
      'currency': offer.currency,
      'createdAt': offer.createdAt.toUtc().toIso8601String(),
      'isActive': offer.isActive,
      'startDate': offer.startDate?.toUtc().toIso8601String(),
      'endDate': offer.endDate?.toUtc().toIso8601String(),
      'imageUrl': offer.imageUrl,
      'globalDiscountMinorUnits': offer.globalDiscount.minorUnits,
      'lines': offer.lines.map(_lineMap).toList(growable: false),
    };
  }

  static Map<String, dynamic> _lineMap(OfferLine line) {
    return <String, dynamic>{
      'id': line.id,
      'productId': line.productId,
      'productName': line.productName,
      'originalUnitPriceMinorUnits': line.originalUnitPrice.minorUnits,
      'finalUnitPriceMinorUnits': line.finalUnitPrice.minorUnits,
      'quantityMilliUnits': line.quantity.milliUnits,
      'unitFactorToBaseMilliUnits': line.unitFactorToBase.milliUnits,
      'priceType': line.priceType.name,
      'unitId': line.unitId,
      'unitName': line.unitName,
      'isService': line.isService,
    };
  }
}
