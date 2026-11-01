import '../../../../core/quantity/quantity.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/inventory_count.dart';

abstract interface class InventoryCountRepository {
  Future<Result<List<InventoryCount>>> listCounts({
    required StoreContext context,
  });

  Future<Result<InventoryCount>> getCount({
    required StoreContext context,
    required String countId,
  });

  Future<Result<InventoryCount>> createCount({
    required StoreContext context,
    required String countId,
    String? categoryId,
    String notes = '',
  });

  Future<Result<InventoryCount>> saveItem({
    required StoreContext context,
    required String countId,
    required int expectedRevision,
    required String productId,
    required Quantity actualQuantity,
    required bool reviewed,
    String reason = '',
    String notes = '',
  });

  Future<Result<InventoryCount>> completeCount({
    required StoreContext context,
    required String countId,
    required int expectedRevision,
  });

  Future<Result<InventoryCount>> cancelCount({
    required StoreContext context,
    required String countId,
    required int expectedRevision,
    required String reason,
  });
}
