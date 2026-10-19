import '../../../../core/money/money.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/journal_entry.dart';

abstract interface class AccountingRepository {
  Future<Result<JournalEntry>> postJournalEntry({
    required StoreContext context,
    required JournalEntry entry,
  });

  Future<Result<Money>> getAccountBalance({
    required StoreContext context,
    required String accountId,
  });
}
