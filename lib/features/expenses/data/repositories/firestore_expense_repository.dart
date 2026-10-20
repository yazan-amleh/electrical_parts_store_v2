import 'package:cloud_functions/cloud_functions.dart' as firebase_functions;

import '../../../../core/commands/command_queue_repository.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../../infrastructure/queue/cloud_function_queue_fallback.dart';
import '../../domain/entities/expense.dart';
import '../../domain/entities/expense_posting_plan.dart';
import '../../domain/repositories/expense_repository.dart';
import '../../domain/services/expense_posting_planner.dart';
import '../mappers/expense_command_mapper.dart';

class FirestoreExpenseRepository implements ExpenseRepository {
  FirestoreExpenseRepository({
    required firebase_functions.FirebaseFunctions functions,
    CommandQueueRepository? commandQueue,
    ExpensePostingPlanner planner = const ExpensePostingPlanner(),
  })  : _functions = functions,
        _commandQueue = commandQueue,
        _planner = planner;

  final firebase_functions.FirebaseFunctions _functions;
  final CommandQueueRepository? _commandQueue;
  final ExpensePostingPlanner _planner;

  @override
  Future<Result<ExpensePostingPlan>> postExpense({
    required StoreContext context,
    required Expense expense,
    required ExpensePostingAccounts accounts,
  }) async {
    final prepared = _planner.prepare(
      context: context,
      expense: expense,
      accounts: accounts,
    );
    if (prepared is FailureResult<ExpensePostingPlan>) {
      return FailureResult<ExpensePostingPlan>(prepared.failure);
    }

    final plan = (prepared as Success<ExpensePostingPlan>).value;
    final payload = ExpenseCommandMapper.toRequest(
      expense: expense,
      accounts: accounts,
    );

    try {
      final callable = _functions.httpsCallable('postExpense');
      final response = await callable.call<Map<String, dynamic>>(payload);
      final data = response.data;
      if (data['expenseId'] != expense.id) {
        return const FailureResult<ExpensePostingPlan>(
          InfrastructureFailure(
            'The expense service returned another expense id.',
          ),
        );
      }

      return Success<ExpensePostingPlan>(plan);
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      if (_commandQueue != null &&
          CloudFunctionQueueFallback.isTransient(error)) {
        final commandId = 'expense-${expense.id}';
        final queueFailure = await CloudFunctionQueueFallback.enqueue(
          repository: _commandQueue,
          context: context,
          commandId: commandId,
          operation: 'postExpense',
          idempotencyKey: expense.idempotencyKey.value,
          payload: payload,
        );
        if (queueFailure != null) {
          return FailureResult<ExpensePostingPlan>(queueFailure);
        }
        return FailureResult<ExpensePostingPlan>(
          QueuedFailure(commandId: commandId),
        );
      }
      return FailureResult<ExpensePostingPlan>(_mapFailure(error));
    } catch (error) {
      return FailureResult<ExpensePostingPlan>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  Failure _mapFailure(firebase_functions.FirebaseFunctionsException error) {
    switch (error.code) {
      case 'permission-denied':
      case 'unauthenticated':
        return AuthorizationFailure(
          error.message ?? 'Expense is not authorized.',
        );
      case 'invalid-argument':
      case 'failed-precondition':
        return ValidationFailure(error.message ?? 'Expense is invalid.');
      case 'already-exists':
      case 'aborted':
        return ConflictFailure(
          error.message ?? 'Expense conflicts with existing data.',
        );
      default:
        return InfrastructureFailure(error.message ?? error.code);
    }
  }
}
