import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' as callable;

import '../../../../core/errors/failure.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../../infrastructure/firebase/firebase_paths.dart';
import '../../domain/entities/inventory_count.dart';
import '../../domain/repositories/inventory_count_repository.dart';

class FirestoreInventoryCountRepository implements InventoryCountRepository {
  FirestoreInventoryCountRepository({
    required FirebaseFirestore firestore,
    required callable.FirebaseFunctions functions,
  })  : _firestore = firestore,
        _functions = functions;

  final FirebaseFirestore _firestore;
  final callable.FirebaseFunctions _functions;

  @override
  Future<Result<List<InventoryCount>>> listCounts({
    required StoreContext context,
  }) async {
    try {
      final snap = await FirebasePaths.inventoryCounts(
        _firestore,
        context.storeId,
      ).limit(50).get();
      final results = snap.docs
          .map((doc) =>
              InventoryCount.fromMap(doc.id, doc.data(), context.storeId))
          .toList(growable: false);
      return Success(results);
    } on FirebaseException catch (error) {
      return FailureResult(InfrastructureFailure(error.message ?? error.code));
    } catch (_) {
      return const FailureResult(
        InfrastructureFailure('تعذر تحميل قائمة الجردات.'),
      );
    }
  }

  @override
  Future<Result<InventoryCount>> getCount({
    required StoreContext context,
    required String countId,
  }) async {
    try {
      if (countId.isEmpty || countId.contains('/')) {
        return const FailureResult(
          ValidationFailure('معرّف الجرد غير صالح.'),
        );
      }
      final snapshot = await FirebasePaths.inventoryCounts(
        _firestore,
        context.storeId,
      ).doc(countId).get();
      if (!snapshot.exists || snapshot.data() == null) {
        return const FailureResult(
          ValidationFailure('لم يتم العثور على الجرد.'),
        );
      }
      return Success(
        InventoryCount.fromMap(countId, snapshot.data()!, context.storeId),
      );
    } on FirebaseException catch (error) {
      return FailureResult(InfrastructureFailure(error.message ?? error.code));
    } catch (_) {
      return const FailureResult(
        InfrastructureFailure('تعذر قراءة بيانات الجرد أو التحقق من مصدرها.'),
      );
    }
  }

  @override
  Future<Result<InventoryCount>> createCount({
    required StoreContext context,
    required String countId,
    String? categoryId,
    String notes = '',
  }) =>
      _mutate(
        'createInventoryCount',
        context,
        countId,
        {
          'categoryId': categoryId,
          'notes': notes,
        },
      );

  @override
  Future<Result<InventoryCount>> saveItem({
    required StoreContext context,
    required String countId,
    required int expectedRevision,
    required String productId,
    required Quantity actualQuantity,
    required bool reviewed,
    String reason = '',
    String notes = '',
  }) =>
      _mutate(
        'updateInventoryCountItem',
        context,
        countId,
        {
          'expectedRevision': expectedRevision,
          'productId': productId,
          'actualQuantityMilliUnits': actualQuantity.milliUnits,
          'reviewed': reviewed,
          'reason': reason,
          'notes': notes,
        },
      );

  @override
  Future<Result<InventoryCount>> completeCount({
    required StoreContext context,
    required String countId,
    required int expectedRevision,
  }) =>
      _mutate(
        'completeInventoryCount',
        context,
        countId,
        {'expectedRevision': expectedRevision},
      );

  @override
  Future<Result<InventoryCount>> cancelCount({
    required StoreContext context,
    required String countId,
    required int expectedRevision,
    required String reason,
  }) =>
      _mutate(
        'cancelInventoryCount',
        context,
        countId,
        {'expectedRevision': expectedRevision, 'reason': reason},
      );

  Future<Result<InventoryCount>> _mutate(
    String action,
    StoreContext context,
    String countId,
    Map<String, dynamic> details,
  ) async {
    if (context.storeId.isEmpty ||
        context.storeId.contains('/') ||
        countId.trim().isEmpty ||
        countId.contains('/')) {
      return const FailureResult(
        ValidationFailure('معرّف المتجر أو الجرد غير صالح.'),
      );
    }
    try {
      final response =
          await _functions.httpsCallable(action).call<Map<String, dynamic>>({
        'storeId': context.storeId,
        'countId': countId,
        ...details,
      });
      final result = Map<String, dynamic>.from(response.data as Map);
      if (result['storeId'] != context.storeId ||
          result['countId'] != countId ||
          result['revision'] is! int) {
        return const FailureResult(
          InfrastructureFailure('استجابة الجرد غير متطابقة مع المتجر.'),
        );
      }
      final loaded = await getCount(context: context, countId: countId);
      if (loaded is Success<InventoryCount> &&
          loaded.value.revision < (result['revision'] as int)) {
        return const FailureResult(
          ConflictFailure('لم يُحدّث الجرد محليًا بعد. يرجى إعادة التحميل.'),
        );
      }
      return loaded;
    } on callable.FirebaseFunctionsException catch (error) {
      switch (error.code) {
        case 'permission-denied':
        case 'unauthenticated':
          return FailureResult(AuthorizationFailure(
            error.message ?? 'ليست لديك صلاحية إدارة الجرد.',
          ));
        case 'aborted':
        case 'already-exists':
          return FailureResult(ConflictFailure(
            error.message ?? 'الجرد تغير في جلسة أخرى. أعد تحميله.',
          ));
        case 'failed-precondition':
        case 'invalid-argument':
        case 'not-found':
          return FailureResult(ValidationFailure(
            error.message ?? 'بيانات الجرد غير صالحة.',
          ));
        default:
          return FailureResult(InfrastructureFailure(
            error.message ?? 'تعذر حفظ الجرد.',
          ));
      }
    } catch (_) {
      return const FailureResult(
        InfrastructureFailure(
          'حالة الحفظ غير مؤكدة. أعد تحميل الجرد قبل تكرار العملية.',
        ),
      );
    }
  }
}
