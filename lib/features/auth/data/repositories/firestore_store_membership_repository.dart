import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../../infrastructure/firebase/firebase_paths.dart';
import '../../domain/entities/store_membership.dart';
import '../../domain/repositories/store_membership_repository.dart';
import '../mappers/store_membership_firestore_mapper.dart';

class FirestoreStoreMembershipRepository implements StoreMembershipRepository {
  FirestoreStoreMembershipRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  @override
  Future<Result<StoreMembership>> getMembership({
    required StoreContext context,
  }) async {
    if (context.storeId.trim().isEmpty ||
        context.storeId.contains('/') ||
        context.userId.trim().isEmpty ||
        context.userId.contains('/')) {
      return const FailureResult<StoreMembership>(
        ValidationFailure('Store or user identity is not configured.'),
      );
    }

    try {
      final snapshot = await FirebasePaths.members(
        _firestore,
        context.storeId,
      ).doc(context.userId).get();

      if (!snapshot.exists) {
        return FailureResult<StoreMembership>(
          StoreMembershipNotFoundFailure(
            'الحساب ${context.userId} غير مضاف إلى المتجر ${context.storeId}. '
            'أضف عضوية نشطة في stores/${context.storeId}/members/${context.userId}.',
          ),
        );
      }

      final data = snapshot.data() ?? const <String, dynamic>{};
      final storedStoreId = data['storeId'];
      if (storedStoreId is String &&
          storedStoreId.trim().isNotEmpty &&
          storedStoreId.trim() != context.storeId) {
        return const FailureResult<StoreMembership>(
          AuthorizationFailure('عضوية المستخدم مرتبطة بمتجر مختلف.'),
        );
      }
      final storedUserId = data['userId'];
      if (storedUserId is String &&
          storedUserId.trim().isNotEmpty &&
          storedUserId.trim() != context.userId) {
        return const FailureResult<StoreMembership>(
          AuthorizationFailure('معرّف المستخدم داخل العضوية غير صحيح.'),
        );
      }

      final membership = StoreMembershipFirestoreMapper.fromSnapshot(
        snapshot: snapshot,
        storeId: context.storeId,
        userId: context.userId,
      );
      if (!membership.canAccessStore) {
        return const FailureResult<StoreMembership>(
          AuthorizationFailure('عضوية المستخدم غير مفعّلة في هذا المتجر.'),
        );
      }

      return Success<StoreMembership>(membership);
    } on FirebaseException catch (error) {
      return FailureResult<StoreMembership>(
        _mapFirebaseFailure(error),
      );
    } catch (error) {
      return FailureResult<StoreMembership>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  Failure _mapFirebaseFailure(FirebaseException error) {
    switch (error.code) {
      case 'permission-denied':
        return const AuthorizationFailure(
          'تعذر قراءة عضوية المتجر. تأكد أن العضوية نشطة وأن قواعد Firestore '
          'منشورة على مشروع Firebase الصحيح.',
        );
      case 'unauthenticated':
        return const AuthorizationFailure(
          'انتهت جلسة Firebase. سجّل الدخول من جديد.',
        );
      case 'unavailable':
      case 'deadline-exceeded':
        return const InfrastructureFailure(
          'تعذر الاتصال بقاعدة بيانات المتجر. تحقق من الإنترنت وحاول مرة أخرى.',
        );
      default:
        return InfrastructureFailure(error.message ?? error.code);
    }
  }
}
