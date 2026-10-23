import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' as firebase_functions;

import '../../../../core/commands/command_queue_repository.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/money/money.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../../infrastructure/firebase/firebase_paths.dart';
import '../../../../infrastructure/queue/cloud_function_queue_fallback.dart';
import '../../domain/entities/journal_entry.dart';
import '../../domain/enums/accounting_enums.dart';
import '../../domain/repositories/accounting_repository.dart';
import '../mappers/account_firestore_mapper.dart';
import '../mappers/account_balance_firestore_mapper.dart';
import '../mappers/journal_entry_command_mapper.dart';

class FirestoreAccountingRepository implements AccountingRepository {
  FirestoreAccountingRepository({
    required FirebaseFirestore firestore,
    required firebase_functions.FirebaseFunctions functions,
    CommandQueueRepository? commandQueue,
  })  : _firestore = firestore,
        _functions = functions,
        _commandQueue = commandQueue;

  final FirebaseFirestore _firestore;
  final firebase_functions.FirebaseFunctions _functions;
  final CommandQueueRepository? _commandQueue;

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
        ValidationFailure('Journal entry identifiers cannot contain a slash.'),
      );
    }

    final payload = JournalEntryCommandMapper.toRequest(entry);

    try {
      final callable = _functions.httpsCallable('postJournalEntry');
      final response = await callable.call<Map<String, dynamic>>(payload);
      if (response.data['entryId'] != entry.id) {
        return const FailureResult<JournalEntry>(
          InfrastructureFailure(
            'The journal service returned another entry id.',
          ),
        );
      }

      return Success<JournalEntry>(entry);
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      if (_commandQueue != null &&
          CloudFunctionQueueFallback.isTransient(error)) {
        final commandId = 'journal-${entry.id}';
        final queueFailure = await CloudFunctionQueueFallback.enqueue(
          repository: _commandQueue,
          context: context,
          commandId: commandId,
          operation: 'postJournalEntry',
          idempotencyKey: entry.idempotencyKey,
          payload: payload,
        );
        if (queueFailure != null) {
          return FailureResult<JournalEntry>(queueFailure);
        }
        return FailureResult<JournalEntry>(QueuedFailure(commandId: commandId));
      }
      return FailureResult<JournalEntry>(_mapFailure(error));
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
          ValidationFailure('Account not found: $accountId'),
        );
      }

      final account = AccountFirestoreMapper.fromSnapshot(accountSnapshot);
      if (account.storeId != context.storeId) {
        return const FailureResult<Money>(
          AuthorizationFailure('Account does not belong to the active store.'),
        );
      }

      final balanceSnapshot = await FirebasePaths.accountBalances(
        _firestore,
        context.storeId,
      ).doc(accountId).get();
      // A missing projection is zero for a new account; an existing malformed
      // projection must never masquerade as zero in a financial UI.
      final projection = balanceSnapshot.exists
          ? AccountBalanceFirestoreMapper.fromMap(
              data: balanceSnapshot.data()!,
              documentAccountId: accountId,
              expectedStoreId: context.storeId,
            )
          : null;
      final debitCreditBalance =
          projection?.debitCreditBalance.minorUnits ?? 0;
      if (projection != null &&
          projection.debit.currency != account.currency) {
        return const FailureResult<Money>(
          ValidationFailure('Account balance currency does not match account.'),
        );
      }
      final normalizedBalance = account.normalSide == NormalSide.debit
          ? debitCreditBalance
          : -debitCreditBalance;

      return Success<Money>(
        Money(minorUnits: normalizedBalance, currency: account.currency),
      );
    } on FirebaseException catch (error) {
      return FailureResult<Money>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<Money>(InfrastructureFailure(error.toString()));
    }
  }

  Failure _mapFailure(firebase_functions.FirebaseFunctionsException error) {
    switch (error.code) {
      case 'permission-denied':
      case 'unauthenticated':
        return AuthorizationFailure(
          error.message ?? 'Journal entry is not authorized.',
        );
      case 'invalid-argument':
      case 'failed-precondition':
        return ValidationFailure(error.message ?? 'Journal entry is invalid.');
      case 'already-exists':
      case 'aborted':
        return ConflictFailure(
          error.message ?? 'Journal entry conflicts with existing data.',
        );
      default:
        return InfrastructureFailure(error.message ?? error.code);
    }
  }

}
