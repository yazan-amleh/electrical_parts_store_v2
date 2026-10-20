import 'dart:typed_data';

import '../../../inventory/domain/entities/product.dart';
import '../entities/category.dart';

abstract interface class CategoryInventoryDocumentBuilder {
  Future<Uint8List> buildInventoryByCategory({
    required List<Category> categories,
    required Map<String, List<Product>> productsByCategory,
    required String storeName,
  });
}
