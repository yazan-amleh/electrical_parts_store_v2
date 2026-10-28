import '../../../../core/money/money.dart';

class ReportTransaction {
  const ReportTransaction({
    required this.id,
    required this.postedAt,
    required this.source,
    required this.amount,
    required this.cost,
    this.tax,
    required this.description,
    required this.paymentMethod,
  });

  final String id;
  final DateTime postedAt;
  final String source;
  final Money amount;
  final Money cost;
  final Money? tax;
  final String? description;
  final String? paymentMethod;

  Money get amountBeforeTax {
    return amount - (tax ?? Money.zero(currency: amount.currency));
  }
}

class OperationalReport {
  const OperationalReport({
    required this.from,
    required this.to,
    required this.salesRevenue,
    required this.salesCost,
    required this.purchasesTotal,
    required this.expensesTotal,
    required this.salesCount,
    this.salesReturnCount = 0,
    required this.purchasesCount,
    required this.expensesCount,
    required this.salesByPaymentMethod,
    required this.expensesByPaymentMethod,
    required this.transactions,
    required this.mayBeTruncated,
  });

  final DateTime from;
  final DateTime to;
  final Money salesRevenue;
  final Money salesCost;
  final Money purchasesTotal;
  final Money expensesTotal;
  final int salesCount;
  final int salesReturnCount;
  final int purchasesCount;
  final int expensesCount;
  final Map<String, int> salesByPaymentMethod;
  final Map<String, int> expensesByPaymentMethod;
  final List<ReportTransaction> transactions;
  final bool mayBeTruncated;

  Money get grossProfit => salesRevenue - salesCost;

  Money get operatingResult => grossProfit - expensesTotal;

  int get transactionCount =>
      salesCount + salesReturnCount + purchasesCount + expensesCount;
}
