import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/money/money.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../../infrastructure/firebase/firebase_paths.dart';
import '../../domain/entities/journal_entry.dart';
import '../../domain/enums/accounting_enums.dart';
import '../../domain/repositories/accounting_repository.dart';
import '../mappers/account_firestore_mapper.dart';
import '../mappers/journal_entry_firestore_mapper.dart';

class FirestoreAccountingRepository implements AccountingRepository {
  FirestoreAccountingRepository({
    required FirebaseFirestore firestore,
  }) : _firestore = firestore;

  final FirebaseFirestore _firestore;

  @override
  Future<Result<JournalEntry>> postJournalEntry({
    required StoreContext context,
    required JournalEntry entry,
  }) async {
    if (entry.storeId != context.storeId) {
      return const FailureResult<JournalEntry>(
        AuthorizationFailure(
          'Journal entry does not belong to the active store.',
        ),
      );
    }
    if (entry.id.contains('/') || entry.idempotencyKey.contains('/')) {
      return const FailureResult<JournalEntry>(
        ValidationFailure(
          'Journal entry identifiers cannot contain a slash.',
        ),
      );
    }

    try {
      return await _firestore.runTransaction<Result<JournalEntry>>(
        (transaction) async {
          final accounts = FirebasePaths.accounts(_firestore, context.storeId);
          final balances = FirebasePaths.accountBalances(
            _firestore,
            context.storeId,
          );
          final journalEntries = FirebasePaths.journalEntries(
            _firestore,
            context.storeId,
          );
          final idempotencyKeys = FirebasePaths.idempotencyKeys(
            _firestore,
            context.storeId,
          );

          final idempotencyReference =
              idempotencyKeys.doc(entry.idempotencyKey);
          final idempotencySnapshot =
              await transaction.get(idempotencyReference);
          if (idempotencySnapshot.exists) {
            final existingEntryId =
                idempotencySnapshot.data()?['entryId'] as String?;
            if (existingEntryId == entry.id) {
              return Success<JournalEntry>(entry);
            }
            return const FailureResult<JournalEntry>(
              ConflictFailure(
                'The idempotency key is already assigned to another entry.',
              ),
            );
          }

          final accountIds = entry.lines
              .map((line) => line.accountId)
              .toSet()
              .toList();
          final accountSnapshots =
              <String, DocumentSnapshot<Map<String, dynamic>>>{};
          final balanceSnapshots =
              <String, DocumentSnapshot<Map<String, dynamic>>>{};

          for (final accountId in accountIds) {
            final accountReference = accounts.doc(accountId);
            accountSnapshots[accountId] =
                await transaction.get(accountReference);
          }
          for (final accountId in accountIds) {
            final balanceReference = balances.doc(accountId);
            balanceSnapshots[accountId] =
                await transaction.get(balanceReference);
          }

          final debitDeltas = <String, int>{};
          final creditDeltas = <String, int>{};

          for (final line in entry.lines) {
            final accountSnapshot = accountSnapshots[line.accountId];
            if (accountSnapshot == null || !accountSnapshot.exists) {
              return FailureResult<JournalEntry>(
                ValidationFailure(
                  'Account not found in current store: ' + line.accountId,
                ),
              );
            }

            final account = AccountFirestoreMapper.fromSnapshot(
              accountSnapshot,
            );
            if (account.storeId != context.storeId) {
              return FailureResult<JournalEntry>(
                AuthorizationFailure(
                  'Account belongs to another store: ' + line.accountId,
                ),
              );
            }
            if (!account.canPost) {
              return FailureResult<JournalEntry>(
                ValidationFailure(
                  'Account is not postable: ' + line.accountId,
                ),
              );
            }
            if (account.currency != line.debit.currency) {
              return FailureResult<JournalEntry>(
                ValidationFailure(
                  'Account currency does not match line currency: ' +
                      line.accountId,
                ),
              );
            }

            debitDeltas.update(
              line.accountId,
              (value) => value + line.debit.minorUnits,
              ifAbsent: () => line.debit.minorUnits,
            );
            creditDeltas.update(
              line.accountId,
              (value) => value + line.credit.minorUnits,
              ifAbsent: () => line.credit.minorUnits,
            );
          }

          final journalReference = journalEntries.doc(entry.id);
          transaction.set(
            journalReference,
            JournalEntryFirestoreMapper.header(entry),
          );

          for (var index = 0; index < entry.lines.length; index++) {
            final line = entry.lines[index];
            transaction.set(
              journalReference.collection('lines').doc(line.id),
              JournalEntryFirestoreMapper.line(
                storeId: context.storeId,
                line: line,
                lineNumber: index + 1,
              ),
            );
          }

          for (final accountId in accountIds) {
            final balanceSnapshot = balanceSnapshots[accountId];
            final balanceData =
                balanceSnapshot?.data() ?? const <String, dynamic>{};
            final currentDebit = _minorUnits(
              balanceData['debitMinorUnits'],
            );
            final currentCredit = _minorUnits(
              balanceData['creditMinorUnits'],
            );
            final nextDebit =
                currentDebit + (debitDeltas[accountId] ?? 0);
            final nextCredit =
                currentCredit + (creditDeltas[accountId] ?? 0);

            transaction.set(
              balances.doc(accountId),
              <String, dynamic>{
                'storeId': context.storeId,
                'accountId': accountId,
                'currency': entry.totalDebit.currency,
                'debitMinorUnits': nextDebit,
                'creditMinorUnits': nextCredit,
                'balanceMinorUnits': nextDebit - nextCredit,
                'updatedAt': FieldValue.serverTimestamp(),
              },
            );
          }

          transaction.set(
            idempotencyReference,
            <String, dynamic>{
              'storeId': context.storeId,
              'entryId': entry.id,
              'idempotencyKey': entry.idempotencyKey,
              'createdAt': FieldValue.serverTimestamp(),
            },
          );

          return Success<JournalEntry>(entry);
        },
      );
    } on FirebaseException catch (error) {
      return FailureResult<JournalEntry>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<JournalEntry>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<Money>> getAccountBalance({
    required StoreContext context,
    required String accountId,
  }) async {
    try {
      final accountSnapshot = await FirebasePaths.accounts(
        _firestore,
        context.storeId,
      ).doc(accountId).get();

      if (!accountSnapshot.exists) {
        return FailureResult<Money>(
          ValidationFailure('Account not found: ' + accountId),
        );
      }

      final account = AccountFirestoreMapper.fromSnapshot(accountSnapshot);
      if (account.storeId != context.storeId) {
        return const FailureResult<Money>(
          AuthorizationFailure(
            'Account does not belong to the active store.',
          ),
        );
      }

      final balanceSnapshot = await FirebasePaths.accountBalances(
        _firestore,
        context.storeId,
      ).doc(accountId).get();
      final balanceData =
          balanceSnapshot.data() ?? const <String, dynamic>{};
      final debit = _minorUnits(balanceData['debitMinorUnits']);
      final credit = _minorUnits(balanceData['creditMinorUnits']);
      final debitCreditBalance = debit - credit;
      final normalizedBalance = account.normalSide == NormalSide.debit
          ? debitCreditBalance
          : -debitCreditBalance;

      return Success<Money>(
        Money(
          minorUnits: normalizedBalance,
          currency: account.currency,
        ),
      );
    } on FirebaseException catch (error) {
      return FailureResult<Money>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<Money>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  static int _minorUnits(Object? value) {
    return value is int ? value : value is num ? value.toInt() : 0;
  }
}
