import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/money/money.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../../infrastructure/firebase/firebase_paths.dart';
import '../../domain/entities/inventory_movement.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../mappers/inventory_movement_firestore_mapper.dart';
import '../mappers/product_firestore_mapper.dart';

class FirestoreInventoryRepository implements InventoryRepository {
  FirestoreInventoryRepository({
    required FirebaseFirestore firestore,
    this.allowNegativeStock = false,
  }) : _firestore = firestore;

  final FirebaseFirestore _firestore;
  final bool allowNegativeStock;

  @override
  Future<Result<InventoryMovement>> postMovement({
    required StoreContext context,
    required InventoryMovement movement,
  }) async {
    if (movement.storeId != context.storeId) {
      return const FailureResult<InventoryMovement>(
        AuthorizationFailure(
          'Inventory movement does not belong to the active store.',
        ),
      );
    }
    if (movement.id.contains('/') ||
        movement.idempotencyKey.contains('/') ||
        movement.productId.contains('/')) {
      return const FailureResult<InventoryMovement>(
        ValidationFailure('Inventory identifiers cannot contain a slash.'),
      );
    }

    try {
      return await _firestore.runTransaction<Result<InventoryMovement>>(
        (transaction) async {
          final productReference = FirebasePaths.products(
            _firestore,
            context.storeId,
          ).doc(movement.productId);
          final movementReference = FirebasePaths.inventoryMovements(
            _firestore,
            context.storeId,
          ).doc(movement.id);
          final idempotencyReference = FirebasePaths.inventoryIdempotency(
            _firestore,
            context.storeId,
          ).doc(movement.idempotencyKey);

          final idempotencySnapshot =
              await transaction.get(idempotencyReference);
          if (idempotencySnapshot.exists) {
            final existingMovementId =
                idempotencySnapshot.data()?['movementId'] as String?;
            if (existingMovementId == movement.id) {
              return Success<InventoryMovement>(movement);
            }
            return const FailureResult<InventoryMovement>(
              ConflictFailure(
                'The inventory idempotency key is already assigned.',
              ),
            );
          }

          final productSnapshot = await transaction.get(productReference);
          if (!productSnapshot.exists) {
            return const FailureResult<InventoryMovement>(
              ValidationFailure('Product was not found.'),
            );
          }

          final product = ProductFirestoreMapper.fromSnapshot(productSnapshot);
          if (product.storeId != context.storeId) {
            return const FailureResult<InventoryMovement>(
              AuthorizationFailure('Product belongs to another store.'),
            );
          }
          if (product.isService) {
            return const FailureResult<InventoryMovement>(
              ValidationFailure('Services cannot receive stock movements.'),
            );
          }
          if (movement.unitCost.currency != product.inventoryValue.currency ||
              movement.totalCost.currency != product.inventoryValue.currency) {
            return const FailureResult<InventoryMovement>(
              ValidationFailure(
                'Inventory movement currency does not match the product.',
              ),
            );
          }

          final nextQuantity = product.quantityOnHand + movement.quantityDelta;
          if (!allowNegativeStock && nextQuantity.isNegative) {
            return const FailureResult<InventoryMovement>(
              ValidationFailure('The movement would create negative stock.'),
            );
          }

          final nextInventoryValue = movement.quantityDelta.isNegative
              ? product.inventoryValue - movement.totalCost
              : product.inventoryValue + movement.totalCost;
          if (nextInventoryValue.isNegative) {
            return const FailureResult<InventoryMovement>(
              ValidationFailure(
                'The movement would create a negative inventory value.',
              ),
            );
          }

          transaction.update(
            productReference,
            <String, dynamic>{
              'quantityOnHandMilliUnits': nextQuantity.milliUnits,
              'inventoryValueMinorUnits': nextInventoryValue.minorUnits,
              'updatedAt': FieldValue.serverTimestamp(),
            },
          );
          transaction.set(
            movementReference,
            InventoryMovementFirestoreMapper.toMap(movement),
          );
          transaction.set(
            idempotencyReference,
            <String, dynamic>{
              'storeId': context.storeId,
              'movementId': movement.id,
              'idempotencyKey': movement.idempotencyKey,
              'createdAt': FieldValue.serverTimestamp(),
            },
          );

          return Success<InventoryMovement>(movement);
        },
      );
    } on FirebaseException catch (error) {
      return FailureResult<InventoryMovement>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<InventoryMovement>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<Quantity>> getOnHand({
    required StoreContext context,
    required String productId,
  }) async {
    try {
      final snapshot = await FirebasePaths.products(
        _firestore,
        context.storeId,
      ).doc(productId).get();
      if (!snapshot.exists) {
        return const FailureResult<Quantity>(
          ValidationFailure('Product was not found.'),
        );
      }

      final product = ProductFirestoreMapper.fromSnapshot(snapshot);
      if (product.storeId != context.storeId) {
        return const FailureResult<Quantity>(
          AuthorizationFailure('Product belongs to another store.'),
        );
      }

      return Success<Quantity>(product.quantityOnHand);
    } on FirebaseException catch (error) {
      return FailureResult<Quantity>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<Quantity>(
        InfrastructureFailure(error.toString()),
      );
    }
  }
}
