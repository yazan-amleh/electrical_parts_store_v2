import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' hide Result;

import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/repositories/store_onboarding_repository.dart';

/// Client may read its own selection; all writes are guarded server callables.
class FirebaseStoreOnboardingRepository implements StoreOnboardingRepository {
  FirebaseStoreOnboardingRepository({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
  })  : _firestore = firestore,
        _functions = functions;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  @override
  Future<Result<String?>> getSelectedStoreId({required String userId}) async {
    if (!_validId(userId)) {
      return const FailureResult<String?>(
        ValidationFailure('معرف المستخدم غير صالح.'),
      );
    }
    try {
      final snapshot = await _firestore
          .collection('user_store_preferences')
          .doc(userId)
          .get(const GetOptions(source: Source.server));
      if (!snapshot.exists) {
        return const Success<String?>(null);
      }
      final storeId = snapshot.data()?['selectedStoreId'];
      if (storeId is! String || !_validId(storeId)) {
        return const FailureResult<String?>(
          ValidationFailure('معرّف المتجر المحفوظ غير صالح.'),
        );
      }
      return Success<String?>(storeId);
    } on FirebaseException catch (error) {
      return FailureResult<String?>(_mapFirestoreError(error));
    } catch (error) {
      return FailureResult<String?>(InfrastructureFailure(error.toString()));
    }
  }

  @override
  Future<Result<String>> createStore({required String name}) async {
    final normalized = name.trim();
    if (normalized.length < 2 || normalized.length > 100) {
      return const FailureResult<String>(
        ValidationFailure('اسم المتجر يجب أن يكون من 2 إلى 100 حرف.'),
      );
    }
    return _call('createStore', {'name': normalized});
  }

  @override
  Future<Result<String>> selectStore({required String storeId}) async {
    if (!_validId(storeId)) {
      return const FailureResult<String>(
        ValidationFailure('معرف المتجر غير صالح.'),
      );
    }
    return _call('selectStore', {'storeId': storeId});
  }

  Future<Result<String>> _call(
    String functionName,
    Map<String, dynamic> data,
  ) async {
    try {
      final callable = _functions.httpsCallable(functionName);
      final response = await callable.call<Map<String, dynamic>>(data);
      final storeId = response.data['storeId'];
      if (storeId is! String || !_validId(storeId)) {
        return const FailureResult<String>(
          InfrastructureFailure('لم ترجع الخدمة معرف متجر صالحًا.'),
        );
      }
      return Success<String>(storeId);
    } on FirebaseFunctionsException catch (error) {
      return FailureResult<String>(_mapFunctionError(error));
    } catch (error) {
      return FailureResult<String>(InfrastructureFailure(error.toString()));
    }
  }

  static bool _validId(String value) =>
      RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(value);

  static Failure _mapFunctionError(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'unauthenticated':
      case 'permission-denied':
        return const AuthorizationFailure(
            'ليس لديك صلاحية الوصول لهذا المتجر.');
      case 'invalid-argument':
        return ValidationFailure(error.message ?? 'بيانات المتجر غير صالحة.');
      case 'already-exists':
      case 'aborted':
        return ConflictFailure(
            error.message ?? 'حدث تعارض أثناء إنشاء المتجر.');
      default:
        return InfrastructureFailure(
          error.message ?? 'تعذّر إتمام العملية مع خادم Firebase.',
        );
    }
  }

  static Failure _mapFirestoreError(FirebaseException error) {
    switch (error.code) {
      case 'permission-denied':
        return const AuthorizationFailure(
          'تعذر قراءة المتجر المحدد. تحقق من صلاحيات Firebase المنشورة.',
        );
      case 'unavailable':
      case 'deadline-exceeded':
        return const InfrastructureFailure('تعذر الاتصال بقاعدة البيانات.');
      default:
        return InfrastructureFailure(error.message ?? error.code);
    }
  }
}
