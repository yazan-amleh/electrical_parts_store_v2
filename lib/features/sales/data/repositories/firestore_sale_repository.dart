import 'package:cloud_functions/cloud_functions.dart' as firebase_functions;

import '../../../../core/commands/command_queue_repository.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../domain/entities/sale.dart';
import '../../domain/entities/sale_posting_plan.dart';
import '../../domain/entities/sale_return.dart';
import '../../domain/repositories/sale_repository.dart';
import '../../../../infrastructure/queue/cloud_function_queue_fallback.dart';
import '../../domain/services/sale_posting_planner.dart';
import '../mappers/sale_command_mapper.dart';
import '../mappers/sale_return_command_mapper.dart';

class FirestoreSaleRepository implements SaleRepository {
  FirestoreSaleRepository({
    required firebase_functions.FirebaseFunctions functions,
    CommandQueueRepository? commandQueue,
    SalePostingPlanner planner = const SalePostingPlanner(),
  })  : _functions = functions,
        _planner = planner,
        _commandQueue = commandQueue;

  final firebase_functions.FirebaseFunctions _functions;
  final SalePostingPlanner _planner;
  final CommandQueueRepository? _commandQueue;

  @override
  Future<Result<SalePostingPlan>> postSale({
    required StoreContext context,
    required Sale sale,
    required SalePostingAccounts accounts,
  }) async {
    final prepared = _planner.prepare(
      context: context,
      sale: sale,
      accounts: accounts,
    );
    if (prepared is FailureResult<SalePostingPlan>) {
      return FailureResult<SalePostingPlan>(prepared.failure);
    }

    final plan = (prepared as Success<SalePostingPlan>).value;

    try {
      final callable = _functions.httpsCallable('postSale');
      final response = await callable.call<Map<String, dynamic>>(
        SaleCommandMapper.toRequest(sale: sale, accounts: accounts),
      );
      final data = response.data;
      if (data['saleId'] != sale.id) {
        return const FailureResult<SalePostingPlan>(
          InfrastructureFailure('The sale service returned another sale id.'),
        );
      }

      return Success<SalePostingPlan>(plan);
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      if (_commandQueue != null &&
          CloudFunctionQueueFallback.isTransient(error)) {
        final commandId = 'sale-${sale.id}';
        final queueFailure = await CloudFunctionQueueFallback.enqueue(
          repository: _commandQueue,
          context: context,
          commandId: commandId,
          operation: 'postSale',
          idempotencyKey: sale.idempotencyKey.value,
          payload: SaleCommandMapper.toRequest(sale: sale, accounts: accounts),
        );
        if (queueFailure != null) {
          return FailureResult<SalePostingPlan>(queueFailure);
        }
        return FailureResult<SalePostingPlan>(
          QueuedFailure(commandId: commandId),
        );
      }
      return FailureResult<SalePostingPlan>(_mapFailure(error));
    } catch (error) {
      return FailureResult<SalePostingPlan>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<SaleReturnPostingResult>> postFullSaleReturn({
    required StoreContext context,
    required SaleReturn saleReturn,
    required SaleReturnPostingAccounts accounts,
  }) async {
    if (saleReturn.storeId != context.storeId) {
      return const FailureResult<SaleReturnPostingResult>(
        ValidationFailure('Sale return belongs to another store.'),
      );
    }

    try {
      final callable = _functions.httpsCallable('postSaleReturn');
      final response = await callable.call<Map<String, dynamic>>(
        SaleReturnCommandMapper.toRequest(
          saleReturn: saleReturn,
          accounts: accounts,
        ),
      );
      final data = response.data;
      if (data['returnId'] != saleReturn.id ||
          data['originalSaleId'] != saleReturn.originalSaleId ||
          data['journalEntryId'] is! String) {
        return const FailureResult<SaleReturnPostingResult>(
          InfrastructureFailure(
            'The sale return service returned inconsistent identifiers.',
          ),
        );
      }
      final status = data['status'];
      if (status != 'returned' && status != 'already_returned') {
        return const FailureResult<SaleReturnPostingResult>(
          InfrastructureFailure('Unexpected sale return status.'),
        );
      }

      return Success<SaleReturnPostingResult>(
        SaleReturnPostingResult(
          returnId: saleReturn.id,
          originalSaleId: saleReturn.originalSaleId,
          journalEntryId: data['journalEntryId'] as String,
          alreadyReturned: status == 'already_returned',
        ),
      );
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      return FailureResult<SaleReturnPostingResult>(_mapFailure(error));
    } catch (error) {
      return FailureResult<SaleReturnPostingResult>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  Failure _mapFailure(firebase_functions.FirebaseFunctionsException error) {
    switch (error.code) {
      case 'permission-denied':
      case 'unauthenticated':
        return AuthorizationFailure(error.message ?? 'Sale is not authorized.');
      case 'invalid-argument':
      case 'failed-precondition':
        return ValidationFailure(error.message ?? 'Sale is invalid.');
      case 'already-exists':
      case 'aborted':
        return ConflictFailure(
          error.message ?? 'Sale conflicts with existing data.',
        );
      default:
        return InfrastructureFailure(error.message ?? error.code);
    }
  }
}
