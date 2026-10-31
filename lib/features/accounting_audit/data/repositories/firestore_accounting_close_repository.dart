import 'package:cloud_functions/cloud_functions.dart' as firebase_functions;

import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';

/// Operates the server-enforced freeze. Does not certify historical balances.
class FirestoreAccountingCloseRepository {
  const FirestoreAccountingCloseRepository({
    required firebase_functions.FirebaseFunctions functions,
  }) : _functions = functions;

  final firebase_functions.FirebaseFunctions _functions;

  Future<Result<Map<String, dynamic>>> status(StoreContext context) =>
      _invoke('getAccountingCloseStatus', context);

  Future<Result<Map<String, dynamic>>> begin(
    StoreContext context,
    String throughDate,
  ) =>
      _invoke(
        'beginAccountingClose',
        context,
        {'throughDate': throughDate},
      );

  Future<Result<Map<String, dynamic>>> startScans(StoreContext context) =>
      _invoke('startAccountingCloseAudits', context);

  Future<Result<Map<String, dynamic>>> advanceScans(StoreContext context) =>
      _invoke('advanceAccountingCloseAudits', context);

  Future<Result<Map<String, dynamic>>> finalize(
    StoreContext context,
    Map<String, dynamic> runIds,
  ) =>
      _invoke('finalizeAccountingClose', context, runIds);

  Future<Result<Map<String, dynamic>>> reopen(
    StoreContext context,
    String reason,
  ) =>
      _invoke('reopenAccountingClose', context, {'reason': reason});

  Future<Result<Map<String, dynamic>>> _invoke(
    String name,
    StoreContext context, [
    Map<String, dynamic> parameters = const {},
  ]) async {
    if (context.storeId.isEmpty || context.storeId.contains('/')) {
      return const FailureResult<Map<String, dynamic>>(
        ValidationFailure('معرّف المتجر غير صالح.'),
      );
    }
    try {
      final response =
          await _functions.httpsCallable(name).call<Map<String, dynamic>>({
        'storeId': context.storeId,
        ...parameters,
      });
      if (response.data['storeId'] != context.storeId ||
          response.data['certified'] != false) {
        return const FailureResult<Map<String, dynamic>>(
          InfrastructureFailure('استجابة الإقفال المحاسبي غير متوقعة.'),
        );
      }
      return Success<Map<String, dynamic>>(response.data);
    } on firebase_functions.FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'unauthenticated':
        case 'permission-denied':
          return FailureResult<Map<String, dynamic>>(
            AuthorizationFailure(e.message ?? 'لا تملك صلاحية الإقفال.'),
          );
        case 'invalid-argument':
        case 'failed-precondition':
        case 'not-found':
          return FailureResult<Map<String, dynamic>>(
            ValidationFailure(e.message ?? 'تعذر تنفيذ عملية الإقفال.'),
          );
        default:
          return FailureResult<Map<String, dynamic>>(
            InfrastructureFailure(e.message ?? e.code),
          );
      }
    } catch (error) {
      return FailureResult<Map<String, dynamic>>(
        InfrastructureFailure(error.toString()),
      );
    }
  }
}
