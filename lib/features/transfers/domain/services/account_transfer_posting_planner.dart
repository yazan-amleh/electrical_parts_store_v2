import '../../../../core/errors/failure.dart';
import '../../../../core/money/money.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../accounting/domain/entities/journal_entry.dart';
import '../../../accounting/domain/entities/journal_line.dart';
import '../entities/account_transfer.dart';
import '../entities/account_transfer_posting_plan.dart';

class AccountTransferPostingPlanner {
  const AccountTransferPostingPlanner();

  Result<AccountTransferPostingPlan> prepare({
    required StoreContext context,
    required AccountTransfer transfer,
  }) {
    if (transfer.storeId != context.storeId) {
      return const FailureResult<AccountTransferPostingPlan>(
        AuthorizationFailure(
          'Account transfer does not belong to the active store.',
        ),
      );
    }

    try {
      final zero = Money.zero(currency: transfer.amount.currency);
      final entry = JournalEntry(
        id: _lineId(transfer.id, 'journal'),
        storeId: transfer.storeId,
        idempotencyKey: _scopeKey(
          transfer.idempotencyKey.value,
          'journal',
        ),
        postedAt: transfer.postedAt,
        sourceType: transfer.sourceType,
        description: transfer.description,
        lines: <JournalLine>[
          JournalLine(
            id: _lineId(transfer.id, 'destination'),
            accountId: transfer.toAccountId,
            debit: transfer.amount,
            credit: zero,
            description: 'Internal account transfer',
          ),
          JournalLine(
            id: _lineId(transfer.id, 'source'),
            accountId: transfer.fromAccountId,
            debit: zero,
            credit: transfer.amount,
            description: 'Internal account transfer',
          ),
        ],
      );

      return Success<AccountTransferPostingPlan>(
        AccountTransferPostingPlan(
          transfer: transfer,
          journalEntry: entry,
        ),
      );
    } on ArgumentError catch (error) {
      return FailureResult<AccountTransferPostingPlan>(
        ValidationFailure(error.message.toString()),
      );
    }
  }

  static String _lineId(String transferId, String suffix) {
    return '$transferId-$suffix';
  }

  static String _scopeKey(String key, String scope) {
    return '$key:$scope';
  }
}
