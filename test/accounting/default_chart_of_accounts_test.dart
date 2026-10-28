import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/features/accounting/domain/enums/accounting_enums.dart';
import 'package:electrical_parts_store_v2/features/accounting/domain/services/default_chart_of_accounts.dart';

void main() {
  test('creates a valid chart for one store', () {
    final accounts = DefaultChartOfAccounts.forStore('store-1');

    expect(accounts, isNotEmpty);
    expect(
      accounts.map((account) => account.code).toSet(),
      hasLength(accounts.length),
    );
    expect(accounts.every((account) => account.storeId == 'store-1'), isTrue);
  });

  test('marks control accounts explicitly', () {
    final accounts = {
      for (final account in DefaultChartOfAccounts.forStore('store-1'))
        account.code: account,
    };

    expect(accounts['1110']!.controlType, ControlType.cashBox);
    expect(accounts['1121']!.controlType, ControlType.bank);
    expect(accounts['1140']!.controlType, ControlType.customerReceivable);
    expect(accounts['1150']!.controlType, ControlType.inventory);
    expect(accounts['1160']!.controlType, ControlType.cardReceivable);
    expect(accounts['1170']!.controlType, ControlType.inputTax);
    expect(accounts['2110']!.controlType, ControlType.supplierPayable);
    expect(accounts['3400']!.normalSide, NormalSide.credit);
    expect(accounts['3400']!.statementSection, StatementSection.equity);
    expect(accounts['4200']!.normalSide, NormalSide.debit);
    expect(accounts['4200']!.statementSection, StatementSection.revenue);
    expect(accounts['5200']!.normalSide, NormalSide.debit);
    expect(accounts['5200']!.statementSection, StatementSection.costOfSales);
  });

  test('header accounts cannot receive journal postings', () {
    final accounts = DefaultChartOfAccounts.forStore('store-1');

    expect(
      accounts.firstWhere((account) => account.code == '1100').canPost,
      isFalse,
    );
    expect(
      accounts.firstWhere((account) => account.code == '1110').canPost,
      isTrue,
    );
  });
}
