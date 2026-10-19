import '../../../../core/money/money.dart';

class AccountLedgerLine {
  const AccountLedgerLine({
    required this.id,
    required this.entryId,
    required this.accountId,
    required this.postedAt,
    required this.debit,
    required this.credit,
    this.description,
  });

  final String id;
  final String entryId;
  final String accountId;
  final DateTime postedAt;
  final Money debit;
  final Money credit;
  final String? description;

  Money get movement => debit - credit;
}
