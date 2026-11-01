import '../../../../core/money/money.dart';
import '../../../../core/quantity/quantity.dart';

enum InventoryCountStatus { draft, completed, approved, rejected, cancelled }

class InventoryCountItem {
  const InventoryCountItem({
    required this.productId,
    required this.productName,
    required this.systemQuantity,
    required this.unitCost,
    this.barcode = '',
    this.actualQuantity,
    this.reviewed = false,
    this.reason = '',
    this.notes = '',
  });

  final String productId;
  final String productName;
  final String barcode;
  final Quantity systemQuantity;
  final Quantity? actualQuantity;
  final Money unitCost;
  final bool reviewed;
  final String reason;
  final String notes;

  Quantity? get difference =>
      actualQuantity == null ? null : actualQuantity! - systemQuantity;

  Money? get estimatedDifference {
    final delta = difference;
    if (delta == null) return null;
    final absolute =
        (delta.milliUnits.abs() * unitCost.minorUnits + 500) ~/ 1000;
    return Money(
      minorUnits: delta.milliUnits.isNegative ? -absolute : absolute,
      currency: unitCost.currency,
    );
  }

  InventoryCountItem copyWith({
    Quantity? actualQuantity,
    bool? reviewed,
    String? reason,
    String? notes,
  }) =>
      InventoryCountItem(
        productId: productId,
        productName: productName,
        barcode: barcode,
        systemQuantity: systemQuantity,
        actualQuantity: actualQuantity ?? this.actualQuantity,
        unitCost: unitCost,
        reviewed: reviewed ?? this.reviewed,
        reason: reason ?? this.reason,
        notes: notes ?? this.notes,
      );

  factory InventoryCountItem.fromMap(Map<String, dynamic> data) {
    final system = data['systemQuantityMilliUnits'];
    final counted = data['actualQuantityMilliUnits'];
    final cost = data['unitCostMinorUnits'];
    if (system is! int ||
        system < 0 ||
        (counted != null && (counted is! int || counted < 0)) ||
        cost is! int ||
        cost < 0) {
      throw const FormatException(
          'Inventory count has invalid numeric values.');
    }
    return InventoryCountItem(
      productId: data['productId'] as String,
      productName: data['productName'] as String,
      barcode: (data['barcode'] as String?) ?? '',
      systemQuantity: Quantity.fromMilliUnits(system),
      actualQuantity:
          counted == null ? null : Quantity.fromMilliUnits(counted as int),
      unitCost: Money(
        minorUnits: cost,
        currency: data['currency'] as String? ?? 'ILS',
      ),
      reviewed: data['reviewed'] == true,
      reason: data['reason'] as String? ?? '',
      notes: data['notes'] as String? ?? '',
    );
  }
}

class InventoryCount {
  InventoryCount({
    required this.id,
    required this.storeId,
    required this.status,
    required this.revision,
    required this.createdBy,
    required List<InventoryCountItem> items,
    this.categoryId,
    this.notes = '',
  }) : items = List.unmodifiable(items);

  final String id;
  final String storeId;
  final InventoryCountStatus status;
  final int revision;
  final String createdBy;
  final String? categoryId;
  final String notes;
  final List<InventoryCountItem> items;

  int get reviewedItems => items.where((item) => item.reviewed).length;
  bool get canComplete =>
      status == InventoryCountStatus.draft &&
      items.isNotEmpty &&
      items.every((item) =>
          item.reviewed &&
          item.actualQuantity != null &&
          (item.difference!.isZero || item.reason.trim().isNotEmpty));

  Map<String, Money> get estimatedDifferenceByCurrency {
    final result = <String, Money>{};
    for (final item in items) {
      final diff = item.estimatedDifference;
      if (diff == null) continue;
      result.update(
        diff.currency,
        (previous) => previous + diff,
        ifAbsent: () => diff,
      );
    }
    return result;
  }

  factory InventoryCount.fromMap(
    String id,
    Map<String, dynamic> data,
    String expectedStoreId,
  ) {
    if (data['storeId'] != expectedStoreId ||
        data['id'] != id ||
        data['revision'] is! int ||
        data['items'] is! List ||
        (data['items'] as List).length > 150) {
      throw const FormatException('Inventory count identity is invalid.');
    }
    final status = InventoryCountStatus.values.where(
      (value) => value.name == data['status'],
    );
    if (status.isEmpty) {
      throw const FormatException('Inventory count status is invalid.');
    }
    final items = (data['items'] as List)
        .map((item) =>
            InventoryCountItem.fromMap(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
    if (items.map((item) => item.productId).toSet().length != items.length) {
      throw const FormatException('Duplicate inventory count product.');
    }
    return InventoryCount(
      id: id,
      storeId: expectedStoreId,
      status: status.single,
      revision: data['revision'] as int,
      createdBy: data['createdBy'] as String,
      items: items,
      categoryId: data['categoryId'] as String?,
      notes: data['notes'] as String? ?? '',
    );
  }
}
