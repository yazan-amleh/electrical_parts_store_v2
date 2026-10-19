enum OfferPriceType {
  retail,
  wholesale,
  custom,
}

OfferPriceType offerPriceTypeFromName(String? value) {
  return OfferPriceType.values.firstWhere(
    (type) => type.name == value,
    orElse: () => OfferPriceType.custom,
  );
}

extension OfferPriceTypeLabel on OfferPriceType {
  String get arabicLabel {
    switch (this) {
      case OfferPriceType.retail:
        return 'سعر التجزئة';
      case OfferPriceType.wholesale:
        return 'سعر الجملة';
      case OfferPriceType.custom:
        return 'سعر مخصص';
    }
  }
}
