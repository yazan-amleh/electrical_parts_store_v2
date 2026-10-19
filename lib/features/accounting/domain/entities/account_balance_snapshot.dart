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
    return normalSide == NormalSide.debit
        ? debitCreditBalance
        : -debitCreditBalance.minorUnits == 0
            ? Money.zero(currency: debit.currency)
            : Money(
                minorUnits: -debitCreditBalance.minorUnits,
                currency: debit.currency,
              );
  }
}
