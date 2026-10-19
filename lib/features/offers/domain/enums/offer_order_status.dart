enum OfferOrderStatus {
  pending,
  confirmed,
  cancelled,
}

OfferOrderStatus offerOrderStatusFromName(String? value) {
  return OfferOrderStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => OfferOrderStatus.pending,
  );
}

extension OfferOrderStatusLabel on OfferOrderStatus {
  String get arabicLabel {
    switch (this) {
      case OfferOrderStatus.pending:
        return 'قيد الانتظار';
      case OfferOrderStatus.confirmed:
        return 'مؤكد';
      case OfferOrderStatus.cancelled:
        return 'ملغي';
    }
  }
}
