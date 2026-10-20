import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/features/accounting/domain/entities/account.dart';
import 'package:electrical_parts_store_v2/features/accounting/domain/entities/financial_statements.dart';
import 'package:electrical_parts_store_v2/features/accounting/domain/entities/trial_balance.dart';
import 'package:electrical_parts_store_v2/features/accounting/domain/enums/accounting_enums.dart';

void main() {
  test(
    'calculates income statement and balance sheet from one trial balance',
    () {
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
      const inventory = Account(
        id: '1150',
        storeId: 'store-1',
        code: '1150',
        name: 'Inventory',
        type: AccountType.asset,
        normalSide: NormalSide.debit,
        controlType: ControlType.inventory,
        statementSection: StatementSection.currentAsset,
      );
      const payable = Account(
        id: '2110',
        storeId: 'store-1',
        code: '2110',
        name: 'Payables',
        type: AccountType.liability,
        normalSide: NormalSide.credit,
        controlType: ControlType.supplierPayable,
        statementSection: StatementSection.currentLiability,
      );
      const capital = Account(
        id: '3110',
        storeId: 'store-1',
        code: '3110',
        name: 'Capital',
        type: AccountType.equity,
        normalSide: NormalSide.credit,
        controlType: ControlType.none,
        statementSection: StatementSection.equity,
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
      const costOfSales = Account(
        id: '5100',
        storeId: 'store-1',
        code: '5100',
        name: 'Cost of sales',
        type: AccountType.expense,
        normalSide: NormalSide.debit,
        controlType: ControlType.none,
        statementSection: StatementSection.costOfSales,
      );
      final trialBalance = TrialBalance(
        lines: [
          TrialBalanceLine(
            account: cash,
            debit: const Money(minorUnits: 50000),
            credit: const Money.zero(),
          ),
          TrialBalanceLine(
            account: inventory,
            debit: const Money(minorUnits: 100000),
            credit: const Money.zero(),
          ),
          TrialBalanceLine(
            account: payable,
            debit: const Money.zero(),
            credit: const Money(minorUnits: 20000),
          ),
          TrialBalanceLine(
            account: capital,
            debit: const Money.zero(),
            credit: const Money(minorUnits: 70000),
          ),
          TrialBalanceLine(
            account: sales,
            debit: const Money.zero(),
            credit: const Money(minorUnits: 100000),
          ),
          TrialBalanceLine(
            account: costOfSales,
            debit: const Money(minorUnits: 40000),
            credit: const Money.zero(),
          ),
        ],
      );
      final statements = FinancialStatements.fromTrialBalance(trialBalance);

      expect(statements.totalAssets.minorUnits, 150000);
      expect(statements.totalLiabilities.minorUnits, 20000);
      expect(statements.totalEquity.minorUnits, 70000);
      expect(statements.grossProfit.minorUnits, 60000);
      expect(statements.netIncome.minorUnits, 60000);
      expect(statements.balanceSheetDifference.minorUnits, 0);
    },
  );
}
