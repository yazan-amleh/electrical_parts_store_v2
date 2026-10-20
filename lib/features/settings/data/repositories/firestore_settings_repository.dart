import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../../infrastructure/firebase/firebase_paths.dart';
import '../../../auth/domain/enums/store_role.dart';
import '../../domain/entities/store_member.dart';
import '../../domain/entities/store_profile.dart';
import '../../domain/repositories/settings_repository.dart';
import '../mappers/store_member_firestore_mapper.dart';
import '../mappers/store_profile_firestore_mapper.dart';

class FirestoreSettingsRepository implements SettingsRepository {
  FirestoreSettingsRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  @override
  Future<Result<StoreProfile>> getStoreProfile({
    required StoreContext context,
  }) async {
    try {
      final snapshot = await FirebasePaths.store(
        _firestore,
        context.storeId,
      ).get();
      if (!snapshot.exists) {
        return const FailureResult<StoreProfile>(
          ValidationFailure('Store profile was not found.'),
        );
      }
      return Success<StoreProfile>(
        StoreProfileFirestoreMapper.fromSnapshot(snapshot),
      );
    } on FirebaseException catch (error) {
      return FailureResult<StoreProfile>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<StoreProfile>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<List<StoreMember>>> getMembers({
    required StoreContext context,
  }) async {
    try {
      final snapshot = await FirebasePaths.members(
        _firestore,
        context.storeId,
      ).get();
      final members = snapshot.docs
          .map(StoreMemberFirestoreMapper.fromSnapshot)
          .toList()
        ..sort((left, right) => left.userId.compareTo(right.userId));
      return Success<List<StoreMember>>(members);
    } on FirebaseException catch (error) {
      return FailureResult<List<StoreMember>>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<List<StoreMember>>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<void>> updateStoreProfile({
    required StoreContext context,
    required StoreProfile profile,
  }) async {
    if (profile.id != context.storeId) {
      return const FailureResult<void>(
        ValidationFailure('Store profile belongs to another store.'),
      );
    }

    try {
      final storeRef = FirebasePaths.store(_firestore, context.storeId);
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(storeRef);
        if (!snapshot.exists) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'not-found',
            message: 'Store profile was not found.',
          );
        }
        final data = snapshot.data() ?? const <String, dynamic>{};
        final existingCurrency = data['currency'];
        if (existingCurrency is String &&
            existingCurrency.trim().isNotEmpty &&
            existingCurrency.trim().toUpperCase() !=
                profile.currency.trim().toUpperCase()) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'failed-precondition',
            message: 'Store currency cannot change after initialization.',
          );
        }
        transaction.update(storeRef, {
          'name': profile.name.trim(),
          'currency': profile.currency.trim().toUpperCase(),
          'phone': profile.phone.trim(),
          'address': profile.address.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      return const Success<void>(null);
    } on FirebaseException catch (error) {
      return FailureResult<void>(
        _mapFirebaseFailure(error, 'Store profile could not be updated.'),
      );
    } catch (error) {
      return FailureResult<void>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<void>> updateMember({
    required StoreContext context,
    required StoreMember member,
  }) async {
    if (member.userId.trim().isEmpty || member.userId.contains('/')) {
      return const FailureResult<void>(
        ValidationFailure('Member id is invalid.'),
      );
    }
    if (member.role == StoreRole.owner) {
      return const FailureResult<void>(
        ValidationFailure('Owner membership cannot be assigned here.'),
      );
    }

    try {
      final memberRef = FirebasePaths.members(
        _firestore,
        context.storeId,
      ).doc(member.userId);
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(memberRef);
        if (!snapshot.exists) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'not-found',
            message: 'Member was not found.',
          );
        }
        final data = snapshot.data() ?? const <String, dynamic>{};
        if (data['role'] == StoreRole.owner.name) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'failed-precondition',
            message: 'The store owner cannot be changed here.',
          );
        }
        transaction.update(memberRef, {
          'role': member.role.name,
          'isActive': member.isActive,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      return const Success<void>(null);
    } on FirebaseException catch (error) {
      return FailureResult<void>(
        _mapFirebaseFailure(error, 'Store member could not be updated.'),
      );
    } catch (error) {
      return FailureResult<void>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  Failure _mapFirebaseFailure(FirebaseException error, String fallback) {
    switch (error.code) {
      case 'permission-denied':
      case 'unauthenticated':
        return AuthorizationFailure(error.message ?? fallback);
      case 'not-found':
      case 'failed-precondition':
        return ValidationFailure(error.message ?? fallback);
      default:
        return InfrastructureFailure(error.message ?? fallback);
    }
  }
}
