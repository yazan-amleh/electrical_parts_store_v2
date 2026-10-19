import 'package:cloud_functions/cloud_functions.dart' as firebase_functions;

import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../domain/entities/party_payment.dart';
import '../../domain/entities/party_payment_posting_plan.dart';
import '../../domain/repositories/party_payment_repository.dart';
import '../../domain/services/party_payment_posting_planner.dart';
import '../mappers/party_payment_command_mapper.dart';

class FirestorePartyPaymentRepository implements PartyPaymentRepository {
  FirestorePartyPaymentRepository({
    required firebase_functions.FirebaseFunctions functions,
    PartyPaymentPostingPlanner planner =
        const PartyPaymentPostingPlanner(),
  })  : _functions = functions,
        _planner = planner;

  final firebase_functions.FirebaseFunctions _functions;
  final PartyPaymentPostingPlanner _planner;

  @override
  Future<Result<PartyPaymentPostingPlan>> postPartyPayment({
    required StoreContext context,
    required PartyPayment payment,
    required PartyPaymentPostingAccounts accounts,
  }) async {
    final prepared = _planner.prepare(
      context: context,
      payment: payment,
      accounts: accounts,
    );
    if (prepared is FailureResult<PartyPaymentPostingPlan>) {
      return FailureResult<PartyPaymentPostingPlan>(prepared.failure);
    }

    final plan = (prepared as Success<PartyPaymentPostingPlan>).value;

    try {
      final callable = _functions.httpsCallable('postPartyPayment');
      final response = await callable.call<Map<String, dynamic>>(
        PartyPaymentCommandMapper.toRequest(
          payment: payment,
          accounts: accounts,
        ),
      );
      final data = response.data;
      if (data['paymentId'] != payment.id) {
        return const FailureResult<PartyPaymentPostingPlan>(
          InfrastructureFailure(
            'The payment service returned another payment id.',
          ),
        );
      }

      return Success<PartyPaymentPostingPlan>(plan);
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      return FailureResult<PartyPaymentPostingPlan>(_mapFailure(error));
    } catch (error) {
      return FailureResult<PartyPaymentPostingPlan>(
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
          error.message ?? 'Party payment is not authorized.',
        );
      case 'invalid-argument':
      case 'failed-precondition':
        return ValidationFailure(
          error.message ?? 'Party payment is invalid.',
        );
      case 'already-exists':
      case 'aborted':
        return ConflictFailure(
          error.message ?? 'Party payment conflicts with existing data.',
        );
      default:
        return InfrastructureFailure(error.message ?? error.code);
    }
  }
}
