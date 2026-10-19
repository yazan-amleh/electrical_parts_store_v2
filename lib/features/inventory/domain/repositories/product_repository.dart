import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/product.dart';

abstract interface class ProductRepository {
  Future<Result<List<Product>>> getProducts({
    required StoreContext context,
    bool includeInactive = false,
  });

  Future<Result<Product>> getProduct({
    required StoreContext context,
    required String productId,
  });

  Future<Result<void>> saveProduct({
    required StoreContext context,
    required Product product,
  });
}
