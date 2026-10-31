import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' as firebase_functions;

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
  FirestoreSettingsRepository({
    required FirebaseFirestore firestore,
    required firebase_functions.FirebaseFunctions functions,
  })  : _firestore = firestore,
        _functions = functions;

  final FirebaseFirestore _firestore;
  final firebase_functions.FirebaseFunctions _functions;

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
      final response = await _functions
          .httpsCallable('updateStoreProfile')
          .call<Map<String, dynamic>>({
        'storeId': context.storeId,
        'profile': <String, dynamic>{
          'name': profile.name.trim(),
          'currency': profile.currency.trim().toUpperCase(),
          'phone': profile.phone.trim(),
          'address': profile.address.trim(),
        },
      });
      if (response.data['storeId'] != context.storeId) {
        return const FailureResult<void>(
          InfrastructureFailure(
            'Store profile service returned another store.',
          ),
        );
      }
      return const Success<void>(null);
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      return FailureResult<void>(
        _mapFunctionFailure(error, 'Store profile could not be updated.'),
      );
    } catch (error) {
      return FailureResult<void>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<void>> addMember({
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
      final response = await _functions
          .httpsCallable('addStoreMember')
          .call<Map<String, dynamic>>({
        'storeId': context.storeId,
        'member': <String, dynamic>{
          'userId': member.userId.trim(),
          'role': member.role.name,
        },
      });
      if (response.data['storeId'] != context.storeId ||
          response.data['userId'] != member.userId.trim()) {
        return const FailureResult<void>(
          InfrastructureFailure(
            'Store member service returned inconsistent data.',
          ),
        );
      }
      return const Success<void>(null);
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      return FailureResult<void>(
        _mapFunctionFailure(error, 'Store member could not be added.'),
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
      final response = await _functions
          .httpsCallable('updateStoreMember')
          .call<Map<String, dynamic>>({
        'storeId': context.storeId,
        'member': <String, dynamic>{
          'userId': member.userId.trim(),
          'role': member.role.name,
          'isActive': member.isActive,
        },
      });
      if (response.data['storeId'] != context.storeId ||
          response.data['userId'] != member.userId.trim()) {
        return const FailureResult<void>(
          InfrastructureFailure(
            'Store member service returned inconsistent data.',
          ),
        );
      }
      return const Success<void>(null);
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      return FailureResult<void>(
        _mapFunctionFailure(error, 'Store member could not be updated.'),
      );
    } catch (error) {
      return FailureResult<void>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  Failure _mapFunctionFailure(
    firebase_functions.FirebaseFunctionsException error,
    String fallback,
  ) {
    switch (error.code) {
      case 'permission-denied':
      case 'unauthenticated':
        return AuthorizationFailure(error.message ?? fallback);
      case 'not-found':
      case 'failed-precondition':
      case 'invalid-argument':
        return ValidationFailure(error.message ?? fallback);
      case 'already-exists':
      case 'aborted':
        return ConflictFailure(error.message ?? fallback);
      default:
        return InfrastructureFailure(error.message ?? error.code);
    }
  }

}
