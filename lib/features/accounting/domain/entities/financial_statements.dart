import '../../../../core/money/money.dart';
import '../enums/accounting_enums.dart';
import 'account.dart';
import 'trial_balance.dart';

class FinancialStatementLine {
  const FinancialStatementLine({required this.account, required this.amount});

  final Account account;
  final Money amount;
}

class FinancialStatements {
  FinancialStatements._({
    required this.currency,
    required this.currentAssets,
    required this.nonCurrentAssets,
    required this.currentLiabilities,
    required this.nonCurrentLiabilities,
    required this.equity,
    required this.revenue,
    required this.costOfSales,
    required this.operatingExpenses,
    required this.otherIncome,
    required this.otherExpenses,
  });

  factory FinancialStatements.fromTrialBalance(TrialBalance trialBalance) {
    final currency = trialBalance.lines.isEmpty
        ? 'ILS'
        : trialBalance.lines.first.account.currency;
    final currentAssets = <FinancialStatementLine>[];
    final nonCurrentAssets = <FinancialStatementLine>[];
    final currentLiabilities = <FinancialStatementLine>[];
    final nonCurrentLiabilities = <FinancialStatementLine>[];
    final equity = <FinancialStatementLine>[];
    final revenue = <FinancialStatementLine>[];
    final costOfSales = <FinancialStatementLine>[];
    final operatingExpenses = <FinancialStatementLine>[];
    final otherIncome = <FinancialStatementLine>[];
    final otherExpenses = <FinancialStatementLine>[];

    for (final line in trialBalance.lines) {
      final statementLine = FinancialStatementLine(
        account: line.account,
        amount: _amountForSection(line),
      );
      switch (line.account.statementSection) {
        case StatementSection.currentAsset:
          currentAssets.add(statementLine);
        case StatementSection.nonCurrentAsset:
          nonCurrentAssets.add(statementLine);
        case StatementSection.currentLiability:
          currentLiabilities.add(statementLine);
        case StatementSection.nonCurrentLiability:
          nonCurrentLiabilities.add(statementLine);
        case StatementSection.equity:
          equity.add(statementLine);
        case StatementSection.revenue:
          revenue.add(statementLine);
        case StatementSection.costOfSales:
          costOfSales.add(statementLine);
        case StatementSection.operatingExpense:
          operatingExpenses.add(statementLine);
        case StatementSection.otherIncome:
          otherIncome.add(statementLine);
        case StatementSection.otherExpense:
          otherExpenses.add(statementLine);
      }
    }

    return FinancialStatements._(
      currency: currency,
      currentAssets: currentAssets,
      nonCurrentAssets: nonCurrentAssets,
      currentLiabilities: currentLiabilities,
      nonCurrentLiabilities: nonCurrentLiabilities,
      equity: equity,
      revenue: revenue,
      costOfSales: costOfSales,
      operatingExpenses: operatingExpenses,
      otherIncome: otherIncome,
      otherExpenses: otherExpenses,
    );
  }

  final String currency;
  final List<FinancialStatementLine> currentAssets;
  final List<FinancialStatementLine> nonCurrentAssets;
  final List<FinancialStatementLine> currentLiabilities;
  final List<FinancialStatementLine> nonCurrentLiabilities;
  final List<FinancialStatementLine> equity;
  final List<FinancialStatementLine> revenue;
  final List<FinancialStatementLine> costOfSales;
  final List<FinancialStatementLine> operatingExpenses;
  final List<FinancialStatementLine> otherIncome;
  final List<FinancialStatementLine> otherExpenses;

  Money get totalCurrentAssets => _sum(currentAssets);
  Money get totalNonCurrentAssets => _sum(nonCurrentAssets);
  Money get totalAssets => totalCurrentAssets + totalNonCurrentAssets;

  Money get totalCurrentLiabilities => _sum(currentLiabilities);
  Money get totalNonCurrentLiabilities => _sum(nonCurrentLiabilities);
  Money get totalLiabilities =>
      totalCurrentLiabilities + totalNonCurrentLiabilities;

  Money get totalEquity => _sum(equity);
  Money get totalRevenue => _sum(revenue);
  Money get totalCostOfSales => _sum(costOfSales);
  Money get grossProfit => totalRevenue - totalCostOfSales;
  Money get totalOperatingExpenses => _sum(operatingExpenses);
  Money get totalOtherIncome => _sum(otherIncome);
  Money get totalOtherExpenses => _sum(otherExpenses);

  Money get netIncome {
    return grossProfit +
        totalOtherIncome -
        totalOperatingExpenses -
        totalOtherExpenses;
  }

  Money get totalLiabilitiesAndEquity {
    return totalLiabilities + totalEquity + netIncome;
  }

  Money get balanceSheetDifference {
    return totalAssets - totalLiabilitiesAndEquity;
  }

  static Money _amountForSection(TrialBalanceLine line) {
    switch (line.account.statementSection) {
      case StatementSection.revenue:
      case StatementSection.otherIncome:
        return line.credit - line.debit;
      case StatementSection.costOfSales:
      case StatementSection.operatingExpense:
      case StatementSection.otherExpense:
        return line.debit - line.credit;
      case StatementSection.currentAsset:
      case StatementSection.nonCurrentAsset:
      case StatementSection.currentLiability:
      case StatementSection.nonCurrentLiability:
      case StatementSection.equity:
        return line.account.normalSide == NormalSide.debit
            ? line.debit - line.credit
            : line.credit - line.debit;
    }
  }

  Money _sum(List<FinancialStatementLine> lines) {
    if (lines.isEmpty) {
      return Money.zero(currency: currency);
    }
    return lines
        .map((line) => line.amount)
        .reduce((left, right) => left + right);
  }
}
