import '../../../../core/money/money.dart';

class JournalLine {
  JournalLine({
    required this.id,
    required this.accountId,
    required this.debit,
    required this.credit,
    this.description,
  }) {
    if (debit.currency != credit.currency) {
      throw ArgumentError('Journal line currencies must match.');
    }
    if (debit.isNegative || credit.isNegative) {
      throw ArgumentError('Debit and credit cannot be negative.');
    }
    if (debit.isZero == credit.isZero) {
      throw ArgumentError('A journal line must contain exactly one side.');
    }
  }

  final String id;
  final String accountId;
  final Money debit;
  final Money credit;
  final String? description;
}
