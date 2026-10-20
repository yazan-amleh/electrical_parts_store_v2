import 'package:cloud_functions/cloud_functions.dart' as firebase_functions;

import '../../../../core/commands/command_queue_repository.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../domain/entities/purchase.dart';
import '../../domain/entities/purchase_posting_plan.dart';
import '../../domain/repositories/purchase_repository.dart';
import '../../../../infrastructure/queue/cloud_function_queue_fallback.dart';
import '../../domain/services/purchase_posting_planner.dart';
import '../mappers/purchase_command_mapper.dart';

class FirestorePurchaseRepository implements PurchaseRepository {
  FirestorePurchaseRepository({
    required firebase_functions.FirebaseFunctions functions,
    CommandQueueRepository? commandQueue,
    PurchasePostingPlanner planner = const PurchasePostingPlanner(),
  }) : _functions = functions,
       _planner = planner,
       _commandQueue = commandQueue;

  final firebase_functions.FirebaseFunctions _functions;
  final PurchasePostingPlanner _planner;
  final CommandQueueRepository? _commandQueue;

  @override
  Future<Result<PurchasePostingPlan>> postPurchase({
    required StoreContext context,
    required Purchase purchase,
    required PurchasePostingAccounts accounts,
  }) async {
    final prepared = _planner.prepare(
      context: context,
      purchase: purchase,
      accounts: accounts,
    );
    if (prepared is FailureResult<PurchasePostingPlan>) {
      return FailureResult<PurchasePostingPlan>(prepared.failure);
    }

    final plan = (prepared as Success<PurchasePostingPlan>).value;

    try {
      final callable = _functions.httpsCallable('postPurchase');
      final response = await callable.call<Map<String, dynamic>>(
        PurchaseCommandMapper.toRequest(purchase: purchase, accounts: accounts),
      );
      final data = response.data;
      if (data['purchaseId'] != purchase.id) {
        return const FailureResult<PurchasePostingPlan>(
          InfrastructureFailure(
            'The purchase service returned another purchase id.',
          ),
        );
      }

      return Success<PurchasePostingPlan>(plan);
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      if (_commandQueue != null &&
          CloudFunctionQueueFallback.isTransient(error)) {
        final commandId = 'purchase-${purchase.id}';
        final queueFailure = await CloudFunctionQueueFallback.enqueue(
          repository: _commandQueue,
          context: context,
          commandId: commandId,
          operation: 'postPurchase',
          idempotencyKey: purchase.idempotencyKey.value,
          payload: PurchaseCommandMapper.toRequest(
            purchase: purchase,
            accounts: accounts,
          ),
        );
        if (queueFailure != null) {
          return FailureResult<PurchasePostingPlan>(queueFailure);
        }
        return FailureResult<PurchasePostingPlan>(
          QueuedFailure(commandId: commandId),
        );
      }
      return FailureResult<PurchasePostingPlan>(_mapFailure(error));
    } catch (error) {
      return FailureResult<PurchasePostingPlan>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  Failure _mapFailure(firebase_functions.FirebaseFunctionsException error) {
    switch (error.code) {
      case 'permission-denied':
      case 'unauthenticated':
        return AuthorizationFailure(
          error.message ?? 'Purchase is not authorized.',
        );
      case 'invalid-argument':
      case 'failed-precondition':
        return ValidationFailure(error.message ?? 'Purchase is invalid.');
      case 'already-exists':
      case 'aborted':
        return ConflictFailure(
          error.message ?? 'Purchase conflicts with existing data.',
        );
      default:
        return InfrastructureFailure(error.message ?? error.code);
    }
  }
}
