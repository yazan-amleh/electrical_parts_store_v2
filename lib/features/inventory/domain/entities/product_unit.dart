import '../../../../core/money/money.dart';
import '../../../../core/quantity/quantity.dart';

class ProductUnit {
  ProductUnit({
    required this.id,
    required this.productId,
    required this.storeId,
    required this.unitId,
    required this.unitName,
    required this.factorToBase,
    required this.retailPrice,
    required this.wholesalePrice,
    this.barcode,
    this.isDefault = false,
    DateTime? createdAt,
  }) : createdAt = (createdAt ?? DateTime.now()).toUtc() {
    if (id.trim().isEmpty ||
        productId.trim().isEmpty ||
        storeId.trim().isEmpty ||
        unitId.trim().isEmpty ||
        unitName.trim().isEmpty) {
      throw ArgumentError('Product unit identity fields are required.');
    }
    if (factorToBase.milliUnits <= 0) {
      throw ArgumentError('Product unit factor must be positive.');
    }
    if (retailPrice.currency != wholesalePrice.currency) {
      throw ArgumentError('Product unit prices must use one currency.');
    }
  }

  final String id;
  final String productId;
  final String storeId;
  final String unitId;
  final String unitName;
  final Quantity factorToBase;
  final Money retailPrice;
  final Money wholesalePrice;
  final String? barcode;
  final bool isDefault;
  final DateTime createdAt;
}
