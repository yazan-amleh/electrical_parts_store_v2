enum RepairPaymentKind {
  advance,
  settlement,
}

extension RepairPaymentKindLabel on RepairPaymentKind {
  String get arabicLabel {
    switch (this) {
      case RepairPaymentKind.advance:
        return 'دفعة مقدمة';
      case RepairPaymentKind.settlement:
        return 'دفعة على الفاتورة';
    }
  }
}
