import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/money/money.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../../infrastructure/firebase/firebase_paths.dart';
import '../../domain/entities/party_ledger_entry.dart';
import '../../domain/enums/party_type.dart';
import '../../domain/repositories/party_ledger_repository.dart';
import '../mappers/party_ledger_entry_firestore_mapper.dart';

class FirestorePartyLedgerRepository implements PartyLedgerRepository {
  FirestorePartyLedgerRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  @override
  Future<Result<List<PartyLedgerEntry>>> getEntries({
    required StoreContext context,
    required PartyType partyType,
    required String partyId,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async {
    if (partyId.trim().isEmpty || partyId.contains('/')) {
      return const FailureResult<List<PartyLedgerEntry>>(
        ValidationFailure('Party id is invalid.'),
      );
    }
    if (limit <= 0 || limit > 500) {
      return const FailureResult<List<PartyLedgerEntry>>(
        ValidationFailure('Party ledger limit must be between 1 and 500.'),
      );
    }

    try {
      Query<Map<String, dynamic>> query =
          FirebasePaths.partyLedgerEntries(_firestore, context.storeId)
              .where('partyType', isEqualTo: partyType.name)
              .where('partyId', isEqualTo: partyId)
              .orderBy('postedAt', descending: true)
              .limit(limit);

      if (from != null) {
        query = query.where(
          'postedAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(from.toUtc()),
        );
      }
      if (to != null) {
        query = query.where(
          'postedAt',
          isLessThanOrEqualTo: Timestamp.fromDate(to.toUtc()),
        );
      }

      final snapshot = await query.get();
      final entries = snapshot.docs
          .map(PartyLedgerEntryFirestoreMapper.fromSnapshot)
          .toList(growable: false);
      for (final entry in entries) {
        if (entry.storeId != context.storeId ||
            entry.partyId != partyId ||
            entry.partyType != partyType) {
          throw const FormatException(
            'Party ledger entry belongs to another tenant or party.',
          );
        }
      }
      entries.sort((left, right) => left.postedAt.compareTo(right.postedAt));
      return Success<List<PartyLedgerEntry>>(entries);
    } on FirebaseException catch (error) {
      return FailureResult<List<PartyLedgerEntry>>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<List<PartyLedgerEntry>>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<Money>> getBalance({
    required StoreContext context,
    required PartyType partyType,
    required String partyId,
    String currency = 'ILS',
  }) async {
    if (partyId.trim().isEmpty || partyId.contains('/')) {
      return const FailureResult<Money>(
        ValidationFailure('Party id is invalid.'),
      );
    }

    try {
      final snapshot = await FirebasePaths.partyBalances(
        _firestore,
        context.storeId,
      ).doc('${partyType.name}-$partyId').get();
      if (!snapshot.exists) {
        return Success<Money>(Money.zero(currency: currency));
      }

      final data = snapshot.data();
      if (data == null ||
          data['storeId'] != context.storeId ||
          data['partyId'] != partyId ||
          data['partyType'] != partyType.name ||
          data['currency'] != currency ||
          data['debitMinorUnits'] is! int ||
          data['creditMinorUnits'] is! int ||
          data['balanceMinorUnits'] is! int) {
        throw const FormatException(
          'Party balance projection identity or amounts are invalid.',
        );
      }
      final debit = data['debitMinorUnits'] as int;
      final credit = data['creditMinorUnits'] as int;
      final balance = data['balanceMinorUnits'] as int;
      if (debit < 0 || credit < 0 || balance != debit - credit) {
        throw const FormatException(
          'Party balance projection does not reconcile.',
        );
      }
      return Success<Money>(
        Money(minorUnits: balance, currency: currency),
      );
    } on FirebaseException catch (error) {
      return FailureResult<Money>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<Money>(InfrastructureFailure(error.toString()));
    }
  }
}
