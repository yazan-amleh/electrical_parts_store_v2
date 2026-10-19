import '../../../../core/idempotency/idempotency_key.dart';
import '../../../../core/money/money.dart';
import '../enums/offer_order_status.dart';
import 'offer_line.dart';

class OfferOrder {
  OfferOrder({
    required this.id,
    required this.storeId,
    required this.orderNumber,
    required this.offerId,
    required this.offerNumber,
    required this.customerId,
    required this.customerName,
    required List<OfferLine> lines,
    required DateTime createdAt,
    this.status = OfferOrderStatus.pending,
    Money? globalDiscount,
    this.saleId,
    this.journalEntryId,
    this.paymentMethod,
    this.confirmedAt,
  })  : lines = List.unmodifiable(lines),
        createdAt = createdAt.toUtc(),
        globalDiscount = globalDiscount ?? const Money.zero(),
        idempotencyKey = IdempotencyKey(id) {
    _ensureIdentifier(id, 'Offer order id');
    _ensureIdentifier(storeId, 'Offer order store id');
    _ensureIdentifier(orderNumber, 'Offer order number');
    _ensureIdentifier(offerId, 'Offer id');
    _ensureIdentifier(customerId, 'Customer id');
    if (customerName.trim().isEmpty) {
      throw ArgumentError('Offer order customer name is required.');
    }
    if (lines.isEmpty) {
      throw ArgumentError('An offer order requires at least one line.');
    }
    if (this.globalDiscount.isNegative ||
        this.globalDiscount.currency != lines.first.currency) {
      throw ArgumentError('Offer order discount is invalid.');
    }
    if (this.globalDiscount.minorUnits > lineFinalTotal.minorUnits) {
      throw ArgumentError('Offer order discount cannot exceed its total.');
    }
    if (status == OfferOrderStatus.confirmed &&
        (saleId == null || journalEntryId == null)) {
      throw ArgumentError('A confirmed offer order needs its posted ids.');
    }
  }

  final String id;
  final String storeId;
  final String orderNumber;
  final String offerId;
  final String offerNumber;
  final String customerId;
  final String customerName;
  final List<OfferLine> lines;
  final DateTime createdAt;
  final OfferOrderStatus status;
  final Money globalDiscount;
  final String? saleId;
  final String? journalEntryId;
  final String? paymentMethod;
  final DateTime? confirmedAt;
  final IdempotencyKey idempotencyKey;

  String get currency => lines.first.currency;

  Money get lineFinalTotal => lines.fold(
        Money.zero(currency: currency),
        (total, line) => total + line.finalTotal,
      );

  Money get total => lineFinalTotal - globalDiscount;

  OfferOrder copyWith({
    OfferOrderStatus? status,
    String? saleId,
    String? journalEntryId,
    String? paymentMethod,
    DateTime? confirmedAt,
  }) {
    return OfferOrder(
      id: id,
      storeId: storeId,
      orderNumber: orderNumber,
      offerId: offerId,
      offerNumber: offerNumber,
      customerId: customerId,
      customerName: customerName,
      lines: lines,
      createdAt: createdAt,
      status: status ?? this.status,
      globalDiscount: globalDiscount,
      saleId: saleId ?? this.saleId,
      journalEntryId: journalEntryId ?? this.journalEntryId,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      confirmedAt: confirmedAt ?? this.confirmedAt,
    );
  }

  static void _ensureIdentifier(String value, String label) {
    if (value.trim().isEmpty || value.contains('/')) {
      throw ArgumentError('$label is invalid.');
    }
  }
}
