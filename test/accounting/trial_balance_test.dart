import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/features/accounting/domain/entities/account.dart';
import 'package:electrical_parts_store_v2/features/accounting/domain/entities/account_balance_snapshot.dart';
import 'package:electrical_parts_store_v2/features/accounting/domain/entities/trial_balance.dart';
import 'package:electrical_parts_store_v2/features/accounting/domain/enums/accounting_enums.dart';

void main() {
  const cash = Account(
    id: '1110',
    storeId: 'store-1',
    code: '1110',
    name: 'Cash',
    type: AccountType.asset,
    normalSide: NormalSide.debit,
    controlType: ControlType.cashBox,
    statementSection: StatementSection.currentAsset,
  );
  const sales = Account(
    id: '4100',
    storeId: 'store-1',
    code: '4100',
    name: 'Sales',
    type: AccountType.revenue,
    normalSide: NormalSide.credit,
    controlType: ControlType.none,
    statementSection: StatementSection.revenue,
  );

  test('normalizes debit and credit account balances', () {
    const snapshot = AccountBalanceSnapshot(
      accountId: '1110',
      debit: Money(minorUnits: 1500),
      credit: Money(minorUnits: 400),
    );

    expect(
      snapshot.normalizedBalance(NormalSide.debit),
      const Money(minorUnits: 1100),
    );
    expect(
      snapshot.normalizedBalance(NormalSide.credit),
      const Money(minorUnits: -1100),
    );
  });

  test('trial balance totals remain balanced from stored debit and credit', () {
    final trialBalance = TrialBalance(
      lines: [
        TrialBalanceLine(
          account: cash,
          debit: const Money(minorUnits: 1000),
          credit: const Money.zero(),
        ),
        TrialBalanceLine(
          account: sales,
          debit: const Money.zero(),
          credit: const Money(minorUnits: 1000),
        ),
      ],
    );

    expect(trialBalance.totalDebit, const Money(minorUnits: 1000));
    expect(trialBalance.totalCredit, const Money(minorUnits: 1000));
    expect(trialBalance.isBalanced, isTrue);
  });
}
