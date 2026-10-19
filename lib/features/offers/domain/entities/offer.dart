import '../../../../core/money/money.dart';
import '../../../../core/tenancy/store_context.dart';
import 'offer_line.dart';

class Offer {
  Offer({
    required this.id,
    required this.storeId,
    required this.offerNumber,
    required this.name,
    required List<OfferLine> lines,
    required DateTime createdAt,
    required this.isActive,
    Money? globalDiscount,
    this.description,
    this.startDate,
    this.endDate,
    this.imageUrl,
  })  : lines = List.unmodifiable(lines),
        createdAt = createdAt.toUtc(),
        globalDiscount = globalDiscount ?? const Money.zero() {
    _ensureIdentifier(id, 'Offer id');
    _ensureIdentifier(storeId, 'Offer store id');
    if (offerNumber.trim().isEmpty) {
      throw ArgumentError('Offer number is required.');
    }
    if (name.trim().isEmpty) {
      throw ArgumentError('Offer name is required.');
    }
    if (this.lines.isEmpty) {
      throw ArgumentError('An offer requires at least one product.');
    }
    final offerCurrency = this.lines.first.currency;
    for (final line in this.lines) {
      if (line.currency != offerCurrency) {
        throw ArgumentError('All offer lines must use one currency.');
      }
    }
    if (this.globalDiscount.currency != offerCurrency ||
        this.globalDiscount.isNegative) {
      throw ArgumentError('Offer discount is invalid.');
    }
    if (this.globalDiscount.minorUnits > lineFinalTotal.minorUnits) {
      throw ArgumentError('Offer discount cannot exceed the offer total.');
    }
    if (startDate != null &&
        endDate != null &&
        startDate!.isAfter(endDate!)) {
      throw ArgumentError('Offer start date must be before its end date.');
    }
  }

  final String id;
  final String storeId;
  final String offerNumber;
  final String name;
  final String? description;
  final List<OfferLine> lines;
  final DateTime createdAt;
  final bool isActive;
  final Money globalDiscount;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? imageUrl;

  String get currency => lines.first.currency;

  Money get originalTotal => lines.fold(
        Money.zero(currency: currency),
        (total, line) => total + line.originalTotal,
      );

  Money get lineDiscountTotal => lines.fold(
        Money.zero(currency: currency),
        (total, line) => total + line.discountTotal,
      );

  Money get lineFinalTotal => lines.fold(
        Money.zero(currency: currency),
        (total, line) => total + line.finalTotal,
      );

  Money get totalDiscount => lineDiscountTotal + globalDiscount;

  Money get totalFinal => lineFinalTotal - globalDiscount;

  double get averageDiscountPercentage {
    if (originalTotal.isZero) {
      return 0;
    }
    return totalDiscount.minorUnits * 100 / originalTotal.minorUnits;
  }

  bool get isCurrentlyActive {
    if (!isActive) {
      return false;
    }
    final now = DateTime.now().toUtc();
    if (startDate != null && now.isBefore(startDate!.toUtc())) {
      return false;
    }
    if (endDate != null && now.isAfter(endDate!.toUtc())) {
      return false;
    }
    return true;
  }

  StoreContext contextFor(String userId) {
    return StoreContext(storeId: storeId, userId: userId);
  }

  Offer copyWith({
    String? id,
    String? storeId,
    String? offerNumber,
    String? name,
    String? description,
    List<OfferLine>? lines,
    DateTime? createdAt,
    bool? isActive,
    Money? globalDiscount,
    DateTime? startDate,
    DateTime? endDate,
    String? imageUrl,
  }) {
    return Offer(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      offerNumber: offerNumber ?? this.offerNumber,
      name: name ?? this.name,
      description: description ?? this.description,
      lines: lines ?? this.lines,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
      globalDiscount: globalDiscount ?? this.globalDiscount,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  static void _ensureIdentifier(String value, String label) {
    if (value.trim().isEmpty || value.contains('/')) {
      throw ArgumentError('$label is invalid.');
    }
  }
}
