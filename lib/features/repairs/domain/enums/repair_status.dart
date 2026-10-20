enum RepairStatus {
  received,
  diagnosing,
  inProgress,
  ready,
  delivered,
  cancelled,
}

extension RepairStatusLabel on RepairStatus {
  String get arabicLabel {
    switch (this) {
      case RepairStatus.received:
        return 'مستلم';
      case RepairStatus.diagnosing:
        return 'قيد الفحص';
      case RepairStatus.inProgress:
        return 'قيد التنفيذ';
      case RepairStatus.ready:
        return 'جاهز للتسليم';
      case RepairStatus.delivered:
        return 'تم التسليم';
      case RepairStatus.cancelled:
        return 'ملغي';
    }
  }
}
