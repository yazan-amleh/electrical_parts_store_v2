import '../../../../core/money/money.dart';

class ReportTransaction {
  const ReportTransaction({
    required this.id,
    required this.postedAt,
    required this.source,
    required this.amount,
    required this.cost,
    required this.description,
    required this.paymentMethod,
  });

  final String id;
  final DateTime postedAt;
  final String source;
  final Money amount;
  final Money cost;
  final String? description;
  final String? paymentMethod;
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
    required this.purchasesCount,
    required this.expensesCount,
    required this.salesByPaymentMethod,
    required this.expensesByPaymentMethod,
    required this.transactions,
  });

  final DateTime from;
  final DateTime to;
  final Money salesRevenue;
  final Money salesCost;
  final Money purchasesTotal;
  final Money expensesTotal;
  final int salesCount;
  final int purchasesCount;
  final int expensesCount;
  final Map<String, int> salesByPaymentMethod;
  final Map<String, int> expensesByPaymentMethod;
  final List<ReportTransaction> transactions;

  Money get grossProfit => salesRevenue - salesCost;

  Money get operatingResult => grossProfit - expensesTotal;

  int get transactionCount => salesCount + purchasesCount + expensesCount;
}
