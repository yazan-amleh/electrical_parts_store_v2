import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../domain/entities/sale.dart';
import '../../domain/entities/sale_posting_plan.dart';
import '../../domain/repositories/sale_repository.dart';
import '../../domain/services/sale_posting_planner.dart';
import '../mappers/sale_command_mapper.dart';

class FirestoreSaleRepository implements SaleRepository {
  FirestoreSaleRepository({
    required FirebaseFunctions functions,
    SalePostingPlanner planner = const SalePostingPlanner(),
  })  : _functions = functions,
        _planner = planner;

  final FirebaseFunctions _functions;
  final SalePostingPlanner _planner;

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
      final response = await callable.call(
        SaleCommandMapper.toRequest(
          sale: sale,
          accounts: accounts,
        ),
      );
      final rawData = response.data;
      if (rawData is! Map) {
        return const FailureResult<SalePostingPlan>(
          InfrastructureFailure(
            'The sale service returned an invalid response.',
          ),
        );
      }

      final data = Map<String, dynamic>.from(rawData);
      if (data['saleId'] != sale.id) {
        return const FailureResult<SalePostingPlan>(
          InfrastructureFailure(
            'The sale service returned another sale id.',
          ),
        );
      }

      return Success<SalePostingPlan>(plan);
    } on FirebaseFunctionsException catch (error) {
      return FailureResult<SalePostingPlan>(_mapFailure(error));
    } catch (error) {
      return FailureResult<SalePostingPlan>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  Failure _mapFailure(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'permission-denied':
      case 'unauthenticated':
        return AuthorizationFailure(
          error.message ?? 'Sale is not authorized.',
        );
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
