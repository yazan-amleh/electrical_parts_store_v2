import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/account.dart';
import '../entities/journal_entry.dart';
import '../entities/posting_result.dart';

class JournalPostingEngine {
  const JournalPostingEngine();

  Result<PostingResult> prepare({
    required StoreContext context,
    required JournalEntry entry,
    required Map<String, Account> accounts,
  }) {
    if (entry.storeId != context.storeId) {
      return const FailureResult(
        ValidationFailure('Journal entry belongs to another store.'),
      );
    }

    try {
      entry.validateForPosting();
    } on ArgumentError catch (error) {
      return FailureResult(ValidationFailure(error.message.toString()));
    }

    final deltas = <String, AccountBalanceDelta>{};

    for (final line in entry.lines) {
      if (line.accountId.trim().isEmpty) {
        return const FailureResult(
          ValidationFailure('Every journal line must have an account.'),
        );
      }

      final account = accounts[line.accountId];
      if (account == null) {
        return FailureResult(
          ValidationFailure('Account not found: ${line.accountId}.'),
        );
      }
      if (account.storeId != context.storeId) {
        return FailureResult(
          ValidationFailure(
            'Account belongs to another store: ${line.accountId}.',
          ),
        );
      }
      if (!account.canPost) {
        return FailureResult(
          ValidationFailure('Account is not postable: ${line.accountId}.'),
        );
      }
      if (account.currency != line.debit.currency ||
          account.currency != line.credit.currency) {
        return FailureResult(
          ValidationFailure(
            'Account currency does not match the journal line: '
            '${line.accountId}.',
          ),
        );
      }

      final previous = deltas[line.accountId];
      if (previous == null) {
        deltas[line.accountId] = AccountBalanceDelta(
          accountId: line.accountId,
          debit: line.debit,
          credit: line.credit,
        );
      } else {
        deltas[line.accountId] = previous.add(
          debitAmount: line.debit,
          creditAmount: line.credit,
        );
      }
    }

    return Success(
      PostingResult(
        entry: entry,
        deltas: deltas.values.toList(growable: false),
      ),
    );
  }
}
