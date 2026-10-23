import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/money/money.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../../infrastructure/firebase/firebase_paths.dart';
import '../../domain/entities/account.dart';
import '../../domain/entities/account_balance_snapshot.dart';
import '../../domain/entities/account_ledger_line.dart';
import '../../domain/entities/trial_balance.dart';
import '../../domain/repositories/accounting_query_repository.dart';
import '../mappers/account_firestore_mapper.dart';
import '../mappers/account_balance_firestore_mapper.dart';

class FirestoreAccountingQueryRepository implements AccountingQueryRepository {
  FirestoreAccountingQueryRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  @override
  Future<Result<List<Account>>> getAccounts({
    required StoreContext context,
    bool includeInactive = false,
  }) async {
    try {
      final snapshot = await FirebasePaths.accounts(
        _firestore,
        context.storeId,
      ).get();

      final accounts = snapshot.docs
          .map(AccountFirestoreMapper.fromSnapshot)
          .where((account) => account.storeId == context.storeId)
          .where((account) => includeInactive || account.isActive)
          .toList()
        ..sort((left, right) {
          final sortOrder = left.sortOrder.compareTo(right.sortOrder);
          return sortOrder == 0 ? left.code.compareTo(right.code) : sortOrder;
        });

      return Success<List<Account>>(accounts);
    } on FirebaseException catch (error) {
      return FailureResult<List<Account>>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<List<Account>>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<List<AccountBalanceSnapshot>>> getAccountBalances({
    required StoreContext context,
  }) async {
    try {
      final snapshot = await FirebasePaths.accountBalances(
        _firestore,
        context.storeId,
      ).get();

      final balances = <AccountBalanceSnapshot>[];
      for (final document in snapshot.docs) {
        balances.add(
          AccountBalanceFirestoreMapper.fromMap(
            data: document.data(),
            documentAccountId: document.id,
            expectedStoreId: context.storeId,
          ),
        );
      }

      return Success<List<AccountBalanceSnapshot>>(balances);
    } on FirebaseException catch (error) {
      return FailureResult<List<AccountBalanceSnapshot>>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<List<AccountBalanceSnapshot>>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<TrialBalance>> getTrialBalance({
    required StoreContext context,
  }) async {
    final accountsResult = await getAccounts(
      context: context,
      includeInactive: true,
    );
    if (accountsResult is FailureResult<List<Account>>) {
      return FailureResult<TrialBalance>(accountsResult.failure);
    }

    final balancesResult = await getAccountBalances(context: context);
    if (balancesResult is FailureResult<List<AccountBalanceSnapshot>>) {
      return FailureResult<TrialBalance>(balancesResult.failure);
    }

    final accounts = (accountsResult as Success<List<Account>>).value;
    final balances = (balancesResult as Success<List<AccountBalanceSnapshot>>)
        .value
        .asMap()
        .map((_, value) => MapEntry(value.accountId, value));

    final accountIds = accounts.map((account) => account.id).toSet();
    for (final balanceId in balances.keys) {
      if (!accountIds.contains(balanceId)) {
        return FailureResult<TrialBalance>(
          ValidationFailure(
            'Account balance exists without a chart account: $balanceId.',
          ),
        );
      }
    }

    final lines = <TrialBalanceLine>[];
    for (final account in accounts.where((account) => !account.isHeader)) {
      final balance = balances[account.id];
      final debit = balance?.debit ?? Money.zero(currency: account.currency);
      final credit = balance?.credit ?? Money.zero(currency: account.currency);

      if (debit.currency != account.currency ||
          credit.currency != account.currency) {
        return FailureResult<TrialBalance>(
          ValidationFailure(
            'Balance currency does not match account ${account.id}.',
          ),
        );
      }

      lines.add(
        TrialBalanceLine(account: account, debit: debit, credit: credit),
      );
    }

    return Success<TrialBalance>(TrialBalance(lines: lines));
  }

  @override
  Future<Result<List<AccountLedgerLine>>> getAccountLedger({
    required StoreContext context,
    required String accountId,
    DateTime? from,
    DateTime? to,
    int limit = 500,
  }) async {
    if (accountId.trim().isEmpty || accountId.contains('/')) {
      return const FailureResult<List<AccountLedgerLine>>(
        ValidationFailure('Account id is invalid.'),
      );
    }
    if (limit <= 0 || limit > 5000) {
      return const FailureResult<List<AccountLedgerLine>>(
        ValidationFailure('Account ledger limit must be between 1 and 5000.'),
      );
    }
    if (from != null && to != null && from.isAfter(to)) {
      return const FailureResult<List<AccountLedgerLine>>(
        ValidationFailure('Ledger start date cannot be after end date.'),
      );
    }

    try {
      final accountSnapshot = await FirebasePaths.accounts(
        _firestore,
        context.storeId,
      ).doc(accountId).get();
      if (!accountSnapshot.exists) {
        return const FailureResult<List<AccountLedgerLine>>(
          ValidationFailure('Account was not found.'),
        );
      }

      final account = AccountFirestoreMapper.fromSnapshot(accountSnapshot);
      if (account.storeId != context.storeId) {
        return const FailureResult<List<AccountLedgerLine>>(
          AuthorizationFailure('Account belongs to another store.'),
        );
      }

      Query<Map<String, dynamic>> query = _firestore
          .collectionGroup('lines')
          .where('storeId', isEqualTo: context.storeId)
          .where('accountId', isEqualTo: accountId)
          .orderBy('postedAt');

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

      final snapshot = await query.limit(limit).get();
      final lines = <AccountLedgerLine>[];
      for (final document in snapshot.docs) {
        final data = document.data();
        // Collection-group 'lines' may also match non-journal line data.
        // Only journal_entries/{entryId}/lines/{lineId} may enter a GL.
        final journalRef = document.reference.parent.parent;
        if (journalRef?.parent.id != 'journal_entries') {
          continue;
        }
        final postedAt = _date(data['postedAt']);
        final entryId = _string(data['entryId']);
        if (postedAt == null ||
            entryId != journalRef!.id ||
            data['storeId'] != context.storeId ||
            data['accountId'] != accountId) {
          throw FormatException(
            'Invalid journal ledger line identity: ${document.id}',
          );
        }
        final currency = data['currency'];
        if (currency is! String || currency != account.currency) {
          throw FormatException(
            'Journal ledger currency mismatch: ${document.id}',
          );
        }
        lines.add(
          AccountLedgerLine(
            id: document.id,
            entryId: entryId,
            accountId: accountId,
            postedAt: postedAt,
            debit: Money(
              minorUnits: _ledgerMinor(data['debitMinorUnits'], document.id),
              currency: currency,
            ),
            credit: Money(
              minorUnits: _ledgerMinor(data['creditMinorUnits'], document.id),
              currency: currency,
            ),
            description: _string(data['description']),
          ),
        );
      }

      return Success<List<AccountLedgerLine>>(lines);
    } on FirebaseException catch (error) {
      return FailureResult<List<AccountLedgerLine>>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<List<AccountLedgerLine>>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  static DateTime? _date(Object? value) {
    if (value is Timestamp) {
      return value.toDate().toUtc();
    }
    if (value is DateTime) {
      return value.toUtc();
    }
    return null;
  }

  static int _ledgerMinor(Object? value, String lineId) {
    if (value is! int ||
        value < 0 ||
        value > AccountBalanceFirestoreMapper.maxSafeMinorUnits) {
      throw FormatException('Invalid money amount on ledger line $lineId');
    }
    return value;
  }

  static String? _string(Object? value, {String? fallback}) {
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return fallback;
  }
}
