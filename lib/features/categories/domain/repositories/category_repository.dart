import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/category.dart';

abstract interface class CategoryRepository {
  Future<Result<List<Category>>> getCategories({
    required StoreContext context,
    bool includeInactive = false,
  });

  Future<Result<void>> saveCategory({
    required StoreContext context,
    required Category category,
  });
}
