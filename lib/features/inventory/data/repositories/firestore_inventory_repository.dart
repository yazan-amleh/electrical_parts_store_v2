import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' as firebase_functions;

import '../../../../core/commands/command_queue_repository.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../../infrastructure/firebase/firebase_paths.dart';
import '../../../../infrastructure/queue/cloud_function_queue_fallback.dart';
import '../../domain/entities/inventory_movement.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../mappers/inventory_movement_command_mapper.dart';
import '../mappers/product_firestore_mapper.dart';

class FirestoreInventoryRepository implements InventoryRepository {
  FirestoreInventoryRepository({
    required FirebaseFirestore firestore,
    required firebase_functions.FirebaseFunctions functions,
    CommandQueueRepository? commandQueue,
  })  : _firestore = firestore,
        _functions = functions,
        _commandQueue = commandQueue;

  final FirebaseFirestore _firestore;
  final firebase_functions.FirebaseFunctions _functions;
  final CommandQueueRepository? _commandQueue;

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

    final payload = InventoryMovementCommandMapper.toRequest(movement);

    try {
      final callable = _functions.httpsCallable('postInventoryMovement');
      final response = await callable.call<Map<String, dynamic>>(payload);
      if (response.data['movementId'] != movement.id) {
        return const FailureResult<InventoryMovement>(
          InfrastructureFailure(
            'The inventory service returned another movement id.',
          ),
        );
      }
      return Success<InventoryMovement>(movement);
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      if (_commandQueue != null &&
          CloudFunctionQueueFallback.isTransient(error)) {
        final commandId = 'inventory-' + movement.id;
        final queueFailure = await CloudFunctionQueueFallback.enqueue(
          repository: _commandQueue!,
          context: context,
          commandId: commandId,
          operation: 'postInventoryMovement',
          idempotencyKey: movement.idempotencyKey,
          payload: payload,
        );
        if (queueFailure != null) {
          return FailureResult<InventoryMovement>(queueFailure);
        }
        return FailureResult<InventoryMovement>(
          QueuedFailure(commandId: commandId),
        );
      }
      return FailureResult<InventoryMovement>(_mapFailure(error));
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

  Failure _mapFailure(
    firebase_functions.FirebaseFunctionsException error,
  ) {
    switch (error.code) {
      case 'permission-denied':
      case 'unauthenticated':
        return AuthorizationFailure(
          error.message ?? 'Inventory movement is not authorized.',
        );
      case 'invalid-argument':
      case 'failed-precondition':
        return ValidationFailure(
          error.message ?? 'Inventory movement is invalid.',
        );
      case 'already-exists':
      case 'aborted':
        return ConflictFailure(
          error.message ?? 'Inventory movement conflicts with existing data.',
        );
      default:
        return InfrastructureFailure(error.message ?? error.code);
    }
  }
}
