import 'package:cloud_functions/cloud_functions.dart' as firebase_functions;

import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../domain/entities/account.dart';
import '../mappers/account_firestore_mapper.dart';

/// Account-chart changes must go through the server transaction so that the
/// same posting epoch guards the four reconciliation scans. No direct
/// Firestore account writes are permitted by V2 security rules.
class FirestoreChartMutationRepository {
  const FirestoreChartMutationRepository({
    required firebase_functions.FirebaseFunctions functions,
  }) : _functions = functions;

  final firebase_functions.FirebaseFunctions _functions;

  Future<Result<Account>> createAccount({
    required StoreContext context,
    required Account account,
  }) async {
    if (account.storeId != context.storeId) {
      return const FailureResult<Account>(
        AuthorizationFailure('Chart account is assigned to another store.'),
      );
    }
    final data = AccountFirestoreMapper.toMap(account)..remove('storeId');
    try {
      final response = await _functions
          .httpsCallable('mutateChartAccount')
          .call<Map<String, dynamic>>({
        'storeId': context.storeId,
        'operation': 'create',
        'account': data,
      });
      if (response.data['accountId'] != account.id ||
          response.data['status'] != 'created') {
        return const FailureResult<Account>(
          InfrastructureFailure('Invalid chart creation confirmation.'),
        );
      }
      return Success<Account>(account);
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      return FailureResult<Account>(_failure(error));
    } catch (error) {
      return FailureResult<Account>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  /// Only editable metadata can be changed. Financial account identity,
  /// currency, control account type and posting classification are immutable.
  Future<Result<String>> updateAccountMetadata({
    required StoreContext context,
    required String accountId,
    required Map<String, dynamic> changes,
  }) async {
    const editable = {
      'name',
      'description',
      'sortOrder',
      'isActive',
      'parentId',
    };
    if (accountId.isEmpty ||
        accountId.contains('/') ||
        changes.isEmpty ||
        changes.keys.any((key) => !editable.contains(key))) {
      return const FailureResult<String>(
        ValidationFailure('Unsupported chart account metadata changes.'),
      );
    }
    try {
      final response = await _functions
          .httpsCallable('mutateChartAccount')
          .call<Map<String, dynamic>>({
        'storeId': context.storeId,
        'operation': 'update',
        'account': {'id': accountId, ...changes},
      });
      final status = response.data['status'];
      if (response.data['accountId'] != accountId ||
          (status != 'updated' && status != 'unchanged')) {
        return const FailureResult<String>(
          InfrastructureFailure('Invalid chart update confirmation.'),
        );
      }
      return Success<String>(status as String);
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      return FailureResult<String>(_failure(error));
    } catch (error) {
      return FailureResult<String>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  Failure _failure(firebase_functions.FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
      case 'permission-denied':
        return AuthorizationFailure(e.message ?? 'Chart access denied.');
      case 'already-exists':
      case 'aborted':
        return ConflictFailure(e.message ?? 'Chart modification conflicts.');
      case 'invalid-argument':
      case 'failed-precondition':
      case 'not-found':
        return ValidationFailure(e.message ?? 'Invalid chart modification.');
      default:
        return InfrastructureFailure(e.message ?? e.code);
    }
  }
}
