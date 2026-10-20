import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../../infrastructure/firebase/firebase_paths.dart';
import '../../domain/entities/party.dart';
import '../../domain/entities/party_balance.dart';
import '../../domain/enums/party_type.dart';
import '../../domain/repositories/party_repository.dart';
import '../mappers/party_firestore_mapper.dart';

class FirestorePartyRepository implements PartyRepository {
  FirestorePartyRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  @override
  Future<Result<List<Party>>> getParties({
    required StoreContext context,
    required PartyType type,
    bool includeInactive = false,
  }) async {
    try {
      Query<Map<String, dynamic>> query = FirebasePaths.parties(
        _firestore,
        context.storeId,
      ).where('partyType', isEqualTo: type.name);
      if (!includeInactive) {
        query = query.where('isActive', isEqualTo: true);
      }

      final snapshot = await query.get();
      final parties = snapshot.docs
          .map(PartyFirestoreMapper.fromSnapshot)
          .where((party) => party.storeId == context.storeId)
          .toList()
        ..sort((left, right) => left.name.compareTo(right.name));
      return Success<List<Party>>(parties);
    } on FirebaseException catch (error) {
      return FailureResult<List<Party>>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<List<Party>>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<Party>> getParty({
    required StoreContext context,
    required String partyId,
  }) async {
    if (partyId.trim().isEmpty || partyId.contains('/')) {
      return const FailureResult<Party>(
        ValidationFailure('Party id is invalid.'),
      );
    }

    try {
      final snapshot = await FirebasePaths.parties(
        _firestore,
        context.storeId,
      ).doc(partyId).get();
      if (!snapshot.exists) {
        return const FailureResult<Party>(
          ValidationFailure('Party was not found.'),
        );
      }

      final party = PartyFirestoreMapper.fromSnapshot(snapshot);
      if (party.storeId != context.storeId) {
        return const FailureResult<Party>(
          AuthorizationFailure('Party belongs to another store.'),
        );
      }
      return Success<Party>(party);
    } on FirebaseException catch (error) {
      return FailureResult<Party>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<Party>(InfrastructureFailure(error.toString()));
    }
  }

  @override
  Future<Result<void>> saveParty({
    required StoreContext context,
    required Party party,
  }) async {
    if (party.storeId != context.storeId) {
      return const FailureResult<void>(
        AuthorizationFailure('Party does not belong to the active store.'),
      );
    }
    if (party.id.contains('/')) {
      return const FailureResult<void>(
        ValidationFailure('Party identifiers cannot contain a slash.'),
      );
    }

    try {
      return await _firestore.runTransaction<Result<void>>((transaction) async {
        final partyReference = FirebasePaths.parties(
          _firestore,
          context.storeId,
        ).doc(party.id);
        final existingSnapshot = await transaction.get(partyReference);
        if (existingSnapshot.exists) {
          final existingParty = PartyFirestoreMapper.fromSnapshot(
            existingSnapshot,
          );
          if (existingParty.storeId != context.storeId) {
            return const FailureResult<void>(
              AuthorizationFailure('Party belongs to another store.'),
            );
          }
          if (existingParty.type != party.type) {
            return const FailureResult<void>(
              ValidationFailure(
                'A party type cannot be changed after creation.',
              ),
            );
          }
        }

        transaction.set(partyReference, PartyFirestoreMapper.toMap(party));
        return const Success<void>(null);
      });
    } on FirebaseException catch (error) {
      return FailureResult<void>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<void>(InfrastructureFailure(error.toString()));
    }
  }

  @override
  Future<Result<Map<String, PartyBalance>>> getBalances({
    required StoreContext context,
    required PartyType type,
  }) async {
    try {
      final snapshot = await FirebasePaths.partyBalances(
        _firestore,
        context.storeId,
      ).where('partyType', isEqualTo: type.name).get();
      final balances = <String, PartyBalance>{};
      for (final document in snapshot.docs) {
        final balance = PartyFirestoreMapper.balanceFromSnapshot(document);
        if (balance.partyId.isEmpty) {
          continue;
        }
        balances[balance.partyId] = balance;
      }
      return Success<Map<String, PartyBalance>>(balances);
    } on FirebaseException catch (error) {
      return FailureResult<Map<String, PartyBalance>>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<Map<String, PartyBalance>>(
        InfrastructureFailure(error.toString()),
      );
    }
  }
}
