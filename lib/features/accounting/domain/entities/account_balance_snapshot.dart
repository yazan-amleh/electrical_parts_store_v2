import '../../../../core/money/money.dart';
import '../enums/accounting_enums.dart';

class AccountBalanceSnapshot {
  const AccountBalanceSnapshot({
    required this.accountId,
    required this.debit,
    required this.credit,
  });

  final String accountId;
  final Money debit;
  final Money credit;

  Money get debitCreditBalance => debit - credit;

  Money normalizedBalance(NormalSide normalSide) {
    final rawBalance = debitCreditBalance.minorUnits;
    return Money(
      minorUnits: normalSide == NormalSide.debit ? rawBalance : -rawBalance,
      currency: debit.currency,
    );
  }
}
