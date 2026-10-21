enum ActivityType {
  saleCreated,
  purchasePosted,
  paymentPosted,
  customerChanged,
  supplierChanged,
  productChanged,
  categoryChanged,
  offerChanged,
  expensePosted,
  repairChanged,
  accountingPosted,
  system,
  other,
}

extension ActivityTypeLabels on ActivityType {
  String get arabicLabel {
    switch (this) {
      case ActivityType.saleCreated:
        return 'مبيعات';
      case ActivityType.purchasePosted:
        return 'مشتريات';
      case ActivityType.paymentPosted:
        return 'دفعات';
      case ActivityType.customerChanged:
        return 'عملاء';
      case ActivityType.supplierChanged:
        return 'موردون';
      case ActivityType.productChanged:
        return 'أصناف';
      case ActivityType.categoryChanged:
        return 'تصنيفات';
      case ActivityType.offerChanged:
        return 'عروض';
      case ActivityType.expensePosted:
        return 'مصروفات';
      case ActivityType.repairChanged:
        return 'صيانة';
      case ActivityType.accountingPosted:
        return 'محاسبة';
      case ActivityType.system:
        return 'نظام';
      case ActivityType.other:
        return 'أخرى';
    }
  }
}

class ActivityLog {
  const ActivityLog({
    required this.id,
    required this.storeId,
    required this.type,
    required this.description,
    required this.occurredAt,
    this.userId,
    this.userName,
    this.metadata = const <String, dynamic>{},
  });

  final String id;
  final String storeId;
  final ActivityType type;
  final String description;
  final DateTime occurredAt;
  final String? userId;
  final String? userName;
  final Map<String, dynamic> metadata;
}
