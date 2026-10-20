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
    try {
      final snapshot = await FirebasePaths.members(
        _firestore,
        context.storeId,
      ).doc(context.userId).get();

      if (!snapshot.exists) {
        return const FailureResult<StoreMembership>(
          AuthorizationFailure('The user is not a member of this store.'),
        );
      }

      final membership = StoreMembershipFirestoreMapper.fromSnapshot(
        snapshot: snapshot,
        storeId: context.storeId,
        userId: context.userId,
      );
      if (!membership.canAccessStore) {
        return const FailureResult<StoreMembership>(
          AuthorizationFailure('The user membership is inactive.'),
        );
      }

      return Success<StoreMembership>(membership);
    } on FirebaseException catch (error) {
      return FailureResult<StoreMembership>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<StoreMembership>(
        InfrastructureFailure(error.toString()),
      );
    }
  }
}
