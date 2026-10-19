import 'package:cloud_functions/cloud_functions.dart' as firebase_functions;

import '../../../../core/commands/command_queue_repository.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../../infrastructure/queue/cloud_function_queue_fallback.dart';
import '../../domain/entities/account_transfer.dart';
import '../../domain/entities/account_transfer_posting_plan.dart';
import '../../domain/repositories/account_transfer_repository.dart';
import '../../domain/services/account_transfer_posting_planner.dart';
import '../mappers/account_transfer_command_mapper.dart';

class FirestoreAccountTransferRepository
    implements AccountTransferRepository {
  FirestoreAccountTransferRepository({
    required firebase_functions.FirebaseFunctions functions,
    CommandQueueRepository? commandQueue,
    AccountTransferPostingPlanner planner =
        const AccountTransferPostingPlanner(),
  })  : _functions = functions,
        _commandQueue = commandQueue,
        _planner = planner;

  final firebase_functions.FirebaseFunctions _functions;
  final CommandQueueRepository? _commandQueue;
  final AccountTransferPostingPlanner _planner;

  @override
  Future<Result<AccountTransferPostingPlan>> postTransfer({
    required StoreContext context,
    required AccountTransfer transfer,
  }) async {
    final prepared = _planner.prepare(
      context: context,
      transfer: transfer,
    );
    if (prepared is FailureResult<AccountTransferPostingPlan>) {
      return FailureResult<AccountTransferPostingPlan>(prepared.failure);
    }

    final plan = (prepared as Success<AccountTransferPostingPlan>).value;
    final payload = AccountTransferCommandMapper.toRequest(
      transfer: transfer,
    );

    try {
      final callable = _functions.httpsCallable('postAccountTransfer');
      final response = await callable.call<Map<String, dynamic>>(payload);
      final data = response.data;
      if (data['transferId'] != transfer.id) {
        return const FailureResult<AccountTransferPostingPlan>(
          InfrastructureFailure(
            'The transfer service returned another transfer id.',
          ),
        );
      }

      return Success<AccountTransferPostingPlan>(plan);
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      if (_commandQueue != null &&
          CloudFunctionQueueFallback.isTransient(error)) {
        final commandId = 'transfer-' + transfer.id;
        final queueFailure = await CloudFunctionQueueFallback.enqueue(
          repository: _commandQueue!,
          context: context,
          commandId: commandId,
          operation: 'postAccountTransfer',
          idempotencyKey: transfer.idempotencyKey.value,
          payload: payload,
        );
        if (queueFailure != null) {
          return FailureResult<AccountTransferPostingPlan>(queueFailure);
        }
        return FailureResult<AccountTransferPostingPlan>(
          QueuedFailure(commandId: commandId),
        );
      }
      return FailureResult<AccountTransferPostingPlan>(_mapFailure(error));
    } catch (error) {
      return FailureResult<AccountTransferPostingPlan>(
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
          error.message ?? 'Account transfer is not authorized.',
        );
      case 'invalid-argument':
      case 'failed-precondition':
        return ValidationFailure(
          error.message ?? 'Account transfer is invalid.',
        );
      case 'already-exists':
      case 'aborted':
        return ConflictFailure(
          error.message ?? 'Account transfer conflicts with existing data.',
        );
      default:
        return InfrastructureFailure(error.message ?? error.code);
    }
  }
}
