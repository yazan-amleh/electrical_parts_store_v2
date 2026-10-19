import '../../../../core/idempotency/idempotency_key.dart';
import '../../../accounting/domain/entities/journal_entry.dart';
import 'account_transfer.dart';

class AccountTransferPostingPlan {
  const AccountTransferPostingPlan({
    required this.transfer,
    required this.journalEntry,
  });

  final AccountTransfer transfer;
  final JournalEntry journalEntry;

  IdempotencyKey get idempotencyKey => transfer.idempotencyKey;
}
