import '../../../../core/quantity/quantity.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/inventory_movement.dart';

abstract interface class InventoryRepository {
  Future<Result<InventoryMovement>> postMovement({
    required StoreContext context,
    required InventoryMovement movement,
  });

  Future<Result<Quantity>> getOnHand({
    required StoreContext context,
    required String productId,
  });
}
