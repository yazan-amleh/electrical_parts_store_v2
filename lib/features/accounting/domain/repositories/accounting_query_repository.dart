import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/account.dart';
import '../entities/account_balance_snapshot.dart';
import '../entities/account_ledger_line.dart';
import '../entities/trial_balance.dart';

abstract interface class AccountingQueryRepository {
  Future<Result<List<Account>>> getAccounts({
    required StoreContext context,
    bool includeInactive = false,
  });

  Future<Result<List<AccountBalanceSnapshot>>> getAccountBalances({
    required StoreContext context,
  });

  Future<Result<TrialBalance>> getTrialBalance({
    required StoreContext context,
  });

  Future<Result<List<AccountLedgerLine>>> getAccountLedger({
    required StoreContext context,
    required String accountId,
    DateTime? from,
    DateTime? to,
    int limit = 500,
  });
}
