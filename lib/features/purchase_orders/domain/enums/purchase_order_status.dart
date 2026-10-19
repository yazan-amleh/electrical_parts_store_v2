enum PurchaseOrderStatus {
  pending,
  completed,
  cancelled,
}

PurchaseOrderStatus purchaseOrderStatusFromName(String? value) {
  return PurchaseOrderStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => PurchaseOrderStatus.pending,
  );
}

extension PurchaseOrderStatusLabels on PurchaseOrderStatus {
  String get arabicLabel {
    switch (this) {
      case PurchaseOrderStatus.pending:
        return 'قيد الانتظار';
      case PurchaseOrderStatus.completed:
        return 'مكتملة';
      case PurchaseOrderStatus.cancelled:
        return 'ملغاة';
    }
  }

  bool get isOpen => this == PurchaseOrderStatus.pending;
}
