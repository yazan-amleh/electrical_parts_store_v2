enum RepairPriority { low, normal, high, urgent }

extension RepairPriorityLabel on RepairPriority {
  String get arabicLabel {
    switch (this) {
      case RepairPriority.low:
        return 'منخفضة';
      case RepairPriority.normal:
        return 'عادية';
      case RepairPriority.high:
        return 'عالية';
      case RepairPriority.urgent:
        return 'عاجلة';
    }
  }
}
