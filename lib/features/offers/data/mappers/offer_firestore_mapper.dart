import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/money/money.dart';
import '../../../../core/quantity/quantity.dart';
import '../../domain/entities/offer.dart';
import '../../domain/entities/offer_line.dart';
import '../../domain/entities/offer_order.dart';
import '../../domain/enums/offer_order_status.dart';
import '../../domain/enums/offer_price_type.dart';

abstract final class OfferFirestoreMapper {
  static Offer fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final currency = _string(data['currency'], 'ILS');
    final rawLines = data['lines'] is List<Object?>
        ? data['lines'] as List<Object?>
        : const <Object?>[];
    final lines = rawLines
        .whereType<Map<String, dynamic>>()
        .map((raw) => _lineFromMap(raw, currency: currency))
        .toList(growable: false);

    return Offer(
      id: snapshot.id,
      storeId: _string(data['storeId']),
      offerNumber: _string(data['offerNumber'], snapshot.id),
      name: _string(data['name'], 'عرض'),
      description: data['description'] as String?,
      lines: lines,
      createdAt:
          _date(data['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      isActive: data['isActive'] != false,
      globalDiscount: Money(
        minorUnits: _int(data['globalDiscountMinorUnits']),
        currency: currency,
      ),
      startDate: _date(data['startDate']),
      endDate: _date(data['endDate']),
      imageUrl: data['imageUrl'] as String?,
    );
  }

  static OfferOrder orderFromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final currency = _string(data['currency'], 'ILS');
    final rawLines = data['lines'] is List<Object?>
        ? data['lines'] as List<Object?>
        : const <Object?>[];
    final lines = rawLines
        .whereType<Map<String, dynamic>>()
        .map((raw) => _lineFromMap(raw, currency: currency))
        .toList(growable: false);

    return OfferOrder(
      id: snapshot.id,
      storeId: _string(data['storeId']),
      orderNumber: _string(data['orderNumber'], snapshot.id),
      offerId: _string(data['offerId']),
      offerNumber: _string(data['offerNumber'], 'عرض'),
      customerId: _string(data['customerId']),
      customerName: _string(data['customerName'], 'عميل'),
      lines: lines,
      createdAt:
          _date(data['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      status: offerOrderStatusFromName(data['status'] as String?),
      globalDiscount: Money(
        minorUnits: _int(data['globalDiscountMinorUnits']),
        currency: currency,
      ),
      saleId: data['saleId'] as String?,
      journalEntryId: data['journalEntryId'] as String?,
      paymentMethod: data['paymentMethod'] as String?,
      confirmedAt: _date(data['confirmedAt']),
    );
  }

  static Map<String, dynamic> toMap(Offer offer) {
    return <String, dynamic>{
      'storeId': offer.storeId,
      'offerNumber': offer.offerNumber,
      'name': offer.name,
      'description': offer.description,
      'currency': offer.currency,
      'createdAt': Timestamp.fromDate(offer.createdAt),
      'isActive': offer.isActive,
      'startDate':
          offer.startDate == null ? null : Timestamp.fromDate(offer.startDate!),
      'endDate':
          offer.endDate == null ? null : Timestamp.fromDate(offer.endDate!),
      'imageUrl': offer.imageUrl,
      'globalDiscountMinorUnits': offer.globalDiscount.minorUnits,
      'totalOriginalMinorUnits': offer.originalTotal.minorUnits,
      'totalDiscountMinorUnits': offer.totalDiscount.minorUnits,
      'totalFinalMinorUnits': offer.totalFinal.minorUnits,
      'lines': offer.lines.map(_lineToMap).toList(growable: false),
    };
  }

  static Map<String, dynamic> orderToMap(OfferOrder order) {
    return <String, dynamic>{
      'storeId': order.storeId,
      'orderNumber': order.orderNumber,
      'offerId': order.offerId,
      'offerNumber': order.offerNumber,
      'customerId': order.customerId,
      'customerName': order.customerName,
      'currency': order.currency,
      'createdAt': Timestamp.fromDate(order.createdAt),
      'status': order.status.name,
      'paymentMethod': order.paymentMethod,
      'globalDiscountMinorUnits': order.globalDiscount.minorUnits,
      'totalMinorUnits': order.total.minorUnits,
      'saleId': order.saleId,
      'journalEntryId': order.journalEntryId,
      'confirmedAt': order.confirmedAt == null
          ? null
          : Timestamp.fromDate(order.confirmedAt!),
      'lines': order.lines.map(_lineToMap).toList(growable: false),
    };
  }

  static OfferLine _lineFromMap(
    Map<String, dynamic> data, {
    required String currency,
  }) {
    final productId = _string(data['productId']);
    return OfferLine(
      id: _string(data['id'], '$productId-line'),
      productId: productId,
      productName: _string(data['productName'], productId),
      originalUnitPrice: Money(
        minorUnits: _int(data['originalUnitPriceMinorUnits']),
        currency: currency,
      ),
      finalUnitPrice: Money(
        minorUnits: _int(
          data['finalUnitPriceMinorUnits'],
          _int(data['unitPriceMinorUnits']),
        ),
        currency: currency,
      ),
      quantity: Quantity.fromMilliUnits(
        _int(data['quantityMilliUnits'], Quantity.scale),
      ),
      unitFactorToBase: Quantity.fromMilliUnits(
        _int(data['unitFactorToBaseMilliUnits'], Quantity.scale),
      ),
      priceType: offerPriceTypeFromName(data['priceType'] as String?),
      unitId: data['unitId'] as String?,
      unitName: data['unitName'] as String?,
      isService: data['isService'] == true,
    );
  }

  static Map<String, dynamic> _lineToMap(OfferLine line) {
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
      'lineOriginalMinorUnits': line.originalTotal.minorUnits,
      'lineFinalMinorUnits': line.finalTotal.minorUnits,
      'lineDiscountMinorUnits': line.discountTotal.minorUnits,
    };
  }

  static String _string(Object? value, [String fallback = '']) {
    return value is String && value.trim().isNotEmpty ? value : fallback;
  }

  static int _int(Object? value, [int fallback = 0]) {
    return value is int
        ? value
        : value is num
            ? value.toInt()
            : fallback;
  }

  static DateTime? _date(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }
}
