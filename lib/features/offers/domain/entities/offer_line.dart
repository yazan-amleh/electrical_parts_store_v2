import '../../../../core/money/money.dart';
import '../../../../core/quantity/quantity.dart';
import '../enums/offer_price_type.dart';

class OfferLine {
  OfferLine({
    required this.id,
    required this.productId,
    required this.productName,
    required this.originalUnitPrice,
    required this.finalUnitPrice,
    required this.quantity,
    required this.unitFactorToBase,
    required this.priceType,
    this.unitId,
    this.unitName,
    this.isService = false,
  }) {
    _ensureIdentifier(id, 'Offer line id');
    _ensureIdentifier(productId, 'Offer product id');
    if (productName.trim().isEmpty) {
      throw ArgumentError('Offer product name is required.');
    }
    if (quantity.milliUnits <= 0) {
      throw ArgumentError('Offer quantity must be positive.');
    }
    if (unitFactorToBase.milliUnits <= 0) {
      throw ArgumentError('Offer unit factor must be positive.');
    }
    if (originalUnitPrice.isNegative || finalUnitPrice.isNegative) {
      throw ArgumentError('Offer prices cannot be negative.');
    }
    if (finalUnitPrice.minorUnits > originalUnitPrice.minorUnits) {
      throw ArgumentError(
        'Offer final price cannot exceed the original price.',
      );
    }
    if (originalUnitPrice.currency != finalUnitPrice.currency) {
      throw ArgumentError('Offer line prices must use one currency.');
    }
    if (unitId != null) {
      _ensureIdentifier(unitId!, 'Offer unit id');
    }
  }

  final String id;
  final String productId;
  final String productName;
  final Money originalUnitPrice;
  final Money finalUnitPrice;
  final Quantity quantity;
  final Quantity unitFactorToBase;
  final OfferPriceType priceType;
  final String? unitId;
  final String? unitName;
  final bool isService;

  String get currency => originalUnitPrice.currency;

  Money get originalTotal => _multiply(originalUnitPrice, quantity);

  Money get finalTotal => _multiply(finalUnitPrice, quantity);

  Money get discountTotal => originalTotal - finalTotal;

  double get discountPercentage {
    if (originalTotal.isZero) {
      return 0;
    }
    return discountTotal.minorUnits * 100 / originalTotal.minorUnits;
  }

  OfferLine copyWith({
    String? id,
    String? productId,
    String? productName,
    Money? originalUnitPrice,
    Money? finalUnitPrice,
    Quantity? quantity,
    Quantity? unitFactorToBase,
    OfferPriceType? priceType,
    String? unitId,
    String? unitName,
    bool? isService,
  }) {
    return OfferLine(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      originalUnitPrice: originalUnitPrice ?? this.originalUnitPrice,
      finalUnitPrice: finalUnitPrice ?? this.finalUnitPrice,
      quantity: quantity ?? this.quantity,
      unitFactorToBase: unitFactorToBase ?? this.unitFactorToBase,
      priceType: priceType ?? this.priceType,
      unitId: unitId ?? this.unitId,
      unitName: unitName ?? this.unitName,
      isService: isService ?? this.isService,
    );
  }

  static Money _multiply(Money amount, Quantity quantity) {
    final numerator = amount.minorUnits * quantity.milliUnits;
    final minorUnits = (numerator + Quantity.scale ~/ 2) ~/ Quantity.scale;
    return Money(minorUnits: minorUnits, currency: amount.currency);
  }

  static void _ensureIdentifier(String value, String label) {
    if (value.trim().isEmpty || value.contains('/')) {
      throw ArgumentError('$label is invalid.');
    }
  }
}
