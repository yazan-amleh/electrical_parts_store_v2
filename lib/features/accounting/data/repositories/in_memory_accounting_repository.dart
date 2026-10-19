import '../../../../core/errors/failure.dart';
import '../../../../core/money/money.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../domain/domain.dart';
import '../../domain/repositories/accounting_repository.dart';
import '../../domain/services/journal_posting_engine.dart';

class InMemoryAccountingRepository implements AccountingRepository {
  InMemoryAccountingRepository({
    required Iterable<Account> accounts,
    JournalPostingEngine engine = const JournalPostingEngine(),
  })  : _accounts = <String, Account>{
          for (final account in accounts) account.id: account,
        },
        _engine = engine;

  final Map<String, Account> _accounts;
  final JournalPostingEngine _engine;
  final Map<String, JournalEntry> _entries = <String, JournalEntry>{};
  final Map<String, String> _idempotencyToEntry = <String, String>{};
  final Map<String, Money> _debitTotals = <String, Money>{};
  final Map<String, Money> _creditTotals = <String, Money>{};

  @override
  Future<Result<JournalEntry>> postJournalEntry({
    required StoreContext context,
    required JournalEntry entry,
  }) async {
    final previousEntryId = _idempotencyToEntry[entry.idempotencyKey];
    if (previousEntryId != null) {
      if (previousEntryId == entry.id) {
        return Success(entry);
      }
      return const FailureResult(
        ConflictFailure('Idempotency key was already used by another entry.'),
      );
    }

    final prepared = _engine.prepare(
      context: context,
      entry: entry,
      accounts: _accounts,
    );
    if (prepared is FailureResult<PostingResult>) {
      return FailureResult(prepared.failure);
    }

    final result = (prepared as Success<PostingResult>).value;
    _entries[entry.id] = entry;
    _idempotencyToEntry[entry.idempotencyKey] = entry.id;

    for (final delta in result.deltas) {
      final account = _accounts[delta.accountId]!;
      final previousDebit = _debitTotals[delta.accountId] ??
          Money.zero(currency: account.currency);
      final previousCredit = _creditTotals[delta.accountId] ??
          Money.zero(currency: account.currency);
      _debitTotals[delta.accountId] = previousDebit + delta.debit;
      _creditTotals[delta.accountId] = previousCredit + delta.credit;
    }

    return Success(entry);
  }

  @override
  Future<Result<Money>> getAccountBalance({
    required StoreContext context,
    required String accountId,
  }) async {
    final account = _accounts[accountId];
    if (account == null || account.storeId != context.storeId) {
      return const FailureResult(
        ValidationFailure('Account was not found in the current store.'),
      );
    }

    final debit =
        _debitTotals[accountId] ?? Money.zero(currency: account.currency);
    final credit =
        _creditTotals[accountId] ?? Money.zero(currency: account.currency);

    final balance = account.normalSide == NormalSide.debit
        ? debit - credit
        : credit - debit;

    return Success(balance);
  }
}
