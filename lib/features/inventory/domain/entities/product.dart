import '../../../../core/money/money.dart';
import '../../../../core/quantity/quantity.dart';
import 'product_unit.dart';

class Product {
  Product({
    required this.id,
    required this.storeId,
    required this.name,
    required this.purchasePrice,
    required this.sellingPrice,
    required this.wholesalePrice,
    required this.quantityOnHand,
    required this.minimumQuantity,
    required this.categoryId,
    this.supplierId,
    this.description = '',
    this.imageUrl = '',
    this.barcode,
    this.sku,
    this.brand,
    this.model,
    this.location,
    this.shelf,
    this.baseUnitId,
    this.baseUnitName,
    this.isService = false,
    this.discountable = true,
    this.expiryDate,
    this.isActive = true,
    List<ProductUnit> units = const [],
  }) : units = List.unmodifiable(units) {
    if (id.trim().isEmpty ||
        storeId.trim().isEmpty ||
        name.trim().isEmpty ||
        categoryId.trim().isEmpty) {
      throw ArgumentError('Product identity fields are required.');
    }
    if (purchasePrice.currency != sellingPrice.currency ||
        purchasePrice.currency != wholesalePrice.currency) {
      throw ArgumentError('Product prices must use one currency.');
    }
    for (final unit in this.units) {
      if (unit.productId != id || unit.storeId != storeId) {
        throw ArgumentError(
            'Product unit belongs to another product or store.');
      }
      if (unit.retailPrice.currency != purchasePrice.currency ||
          unit.wholesalePrice.currency != purchasePrice.currency) {
        throw ArgumentError('Product unit currency does not match product.');
      }
    }
  }

  final String id;
  final String storeId;
  final String name;
  final Money purchasePrice;
  final Money sellingPrice;
  final Money wholesalePrice;
  final Quantity quantityOnHand;
  final Quantity minimumQuantity;
  final String categoryId;
  final String? supplierId;
  final String description;
  final String imageUrl;
  final String? barcode;
  final String? sku;
  final String? brand;
  final String? model;
  final String? location;
  final String? shelf;
  final String? baseUnitId;
  final String? baseUnitName;
  final bool isService;
  final bool discountable;
  final DateTime? expiryDate;
  final bool isActive;
  final List<ProductUnit> units;

  bool get isLowStock {
    return !isService &&
        quantityOnHand.milliUnits <= minimumQuantity.milliUnits;
  }
}
