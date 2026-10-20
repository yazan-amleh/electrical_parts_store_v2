import 'package:cloud_functions/cloud_functions.dart' as firebase_functions;

import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../domain/entities/accounting_audit_report.dart';
import '../../domain/repositories/accounting_audit_repository.dart';

class FirestoreAccountingAuditRepository
    implements AccountingAuditRepository {
  FirestoreAccountingAuditRepository({
    required firebase_functions.FirebaseFunctions functions,
  }) : _functions = functions;

  final firebase_functions.FirebaseFunctions _functions;

  @override
  Future<Result<AccountingAuditReport>> runAudit({
    required StoreContext context,
  }) async {
    if (context.storeId.trim().isEmpty || context.storeId.contains('/')) {
      return const FailureResult<AccountingAuditReport>(
        ValidationFailure('Store id is invalid.'),
      );
    }

    try {
      final response = await _functions
          .httpsCallable('auditAccountingIntegrity')
          .call<Map<String, dynamic>>({
        'storeId': context.storeId,
      });
      return Success<AccountingAuditReport>(
        AccountingAuditReport.fromMap(response.data),
      );
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      return FailureResult<AccountingAuditReport>(_mapFailure(error));
    } catch (error) {
      return FailureResult<AccountingAuditReport>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  Failure _mapFailure(firebase_functions.FirebaseFunctionsException error) {
    switch (error.code) {
      case 'permission-denied':
      case 'unauthenticated':
        return AuthorizationFailure(
          error.message ?? 'Accounting audit is not authorized.',
        );
      case 'invalid-argument':
      case 'failed-precondition':
        return ValidationFailure(
          error.message ?? 'Accounting audit request is invalid.',
        );
      default:
        return InfrastructureFailure(error.message ?? error.code);
    }
  }
}
