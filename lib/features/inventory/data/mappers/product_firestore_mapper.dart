import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/money/money.dart';
import '../../../../core/quantity/quantity.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/product_unit.dart';

abstract final class ProductFirestoreMapper {
  static Product fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final storeId = _string(data['storeId'], '');
    final currency = _string(data['currency'], 'ILS');

    return Product(
      id: snapshot.id,
      storeId: storeId,
      name: _string(data['name'], snapshot.id),
      purchasePrice: Money(
        minorUnits: _int(data['purchasePriceMinorUnits']),
        currency: currency,
      ),
      sellingPrice: Money(
        minorUnits: _int(data['sellingPriceMinorUnits']),
        currency: currency,
      ),
      wholesalePrice: Money(
        minorUnits: _int(data['wholesalePriceMinorUnits']),
        currency: currency,
      ),
      quantityOnHand: Quantity.fromMilliUnits(
        _int(data['quantityOnHandMilliUnits']),
      ),
      minimumQuantity: Quantity.fromMilliUnits(
        _int(data['minimumQuantityMilliUnits'], 5000),
      ),
      categoryId: _string(data['categoryId'], ''),
      supplierId: data['supplierId'] as String?,
      description: _string(data['description'], ''),
      imageUrl: _string(data['imageUrl'], ''),
      barcode: data['barcode'] as String?,
      sku: data['sku'] as String?,
      brand: data['brand'] as String?,
      model: data['model'] as String?,
      location: data['location'] as String?,
      shelf: data['shelf'] as String?,
      baseUnitId: data['baseUnitId'] as String?,
      baseUnitName: data['baseUnitName'] as String?,
      isService: data['isService'] is bool ? data['isService'] as bool : false,
      discountable:
          data['discountable'] is bool ? data['discountable'] as bool : true,
      expiryDate: _date(data['expiryDate']),
      isActive: data['isActive'] is bool ? data['isActive'] as bool : true,
      units: _units(
        data['units'],
        productId: snapshot.id,
        storeId: storeId,
        currency: currency,
      ),
    );
  }

  static Map<String, dynamic> toMap(Product product) {
    return <String, dynamic>{
      'storeId': product.storeId,
      'name': product.name,
      'currency': product.sellingPrice.currency,
      'purchasePriceMinorUnits': product.purchasePrice.minorUnits,
      'sellingPriceMinorUnits': product.sellingPrice.minorUnits,
      'wholesalePriceMinorUnits': product.wholesalePrice.minorUnits,
      'quantityOnHandMilliUnits': product.quantityOnHand.milliUnits,
      'minimumQuantityMilliUnits': product.minimumQuantity.milliUnits,
      'categoryId': product.categoryId,
      'supplierId': product.supplierId,
      'description': product.description,
      'imageUrl': product.imageUrl,
      'barcode': product.barcode,
      'sku': product.sku,
      'brand': product.brand,
      'model': product.model,
      'location': product.location,
      'shelf': product.shelf,
      'baseUnitId': product.baseUnitId,
      'baseUnitName': product.baseUnitName,
      'isService': product.isService,
      'discountable': product.discountable,
      'expiryDate': product.expiryDate == null
          ? null
          : Timestamp.fromDate(product.expiryDate!.toUtc()),
      'isActive': product.isActive,
      'units': product.units.map(_unitToMap).toList(),
    };
  }

  static List<ProductUnit> _units(
    Object? raw, {
    required String productId,
    required String storeId,
    required String currency,
  }) {
    if (raw is! List) {
      return const [];
    }

    return raw
        .whereType<Map<String, dynamic>>()
        .map(
          (value) => _unitFromMap(
            value.cast<String, dynamic>(),
            productId: productId,
            storeId: storeId,
            currency: currency,
          ),
        )
        .toList();
  }

  static ProductUnit _unitFromMap(
    Map<String, dynamic> data, {
    required String productId,
    required String storeId,
    required String currency,
  }) {
    return ProductUnit(
      id: _string(data['id'], '$productId-unit'),
      productId: productId,
      storeId: storeId,
      unitId: _string(data['unitId'], ''),
      unitName: _string(data['unitName'], ''),
      factorToBase: Quantity.fromMilliUnits(
        _int(data['factorToBaseMilliUnits'], Quantity.scale),
      ),
      retailPrice: Money(
        minorUnits: _int(data['retailPriceMinorUnits']),
        currency: currency,
      ),
      wholesalePrice: Money(
        minorUnits: _int(data['wholesalePriceMinorUnits']),
        currency: currency,
      ),
      barcode: data['barcode'] as String?,
      isDefault: data['isDefault'] is bool ? data['isDefault'] as bool : false,
      createdAt: _date(data['createdAt']),
    );
  }

  static Map<String, dynamic> _unitToMap(ProductUnit unit) {
    return <String, dynamic>{
      'id': unit.id,
      'productId': unit.productId,
      'storeId': unit.storeId,
      'unitId': unit.unitId,
      'unitName': unit.unitName,
      'factorToBaseMilliUnits': unit.factorToBase.milliUnits,
      'retailPriceMinorUnits': unit.retailPrice.minorUnits,
      'wholesalePriceMinorUnits': unit.wholesalePrice.minorUnits,
      'barcode': unit.barcode,
      'isDefault': unit.isDefault,
      'createdAt': Timestamp.fromDate(unit.createdAt),
    };
  }

  static DateTime? _date(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }

  static String _string(Object? value, String fallback) {
    return value is String && value.isNotEmpty ? value : fallback;
  }

  static int _int(Object? value, [int fallback = 0]) {
    return value is int
        ? value
        : value is num
            ? value.toInt()
            : fallback;
  }
}
