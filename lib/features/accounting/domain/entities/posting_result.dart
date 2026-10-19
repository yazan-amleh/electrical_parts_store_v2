import '../../../../core/money/money.dart';

import 'journal_entry.dart';

class AccountBalanceDelta {
  const AccountBalanceDelta({
    required this.accountId,
    required this.debit,
    required this.credit,
  });

  final String accountId;
  final Money debit;
  final Money credit;

  AccountBalanceDelta add({
    required Money debitAmount,
    required Money creditAmount,
  }) {
    return AccountBalanceDelta(
      accountId: accountId,
      debit: debit + debitAmount,
      credit: credit + creditAmount,
    );
  }
}

class PostingResult {
  PostingResult({
    required this.entry,
    required List<AccountBalanceDelta> deltas,
  }) : deltas = List.unmodifiable(deltas);

  final JournalEntry entry;
  final List<AccountBalanceDelta> deltas;
}
