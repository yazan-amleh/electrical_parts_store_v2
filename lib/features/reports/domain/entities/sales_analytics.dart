import '../../../../core/money/money.dart';

class SalesAnalyticsRow {
  const SalesAnalyticsRow({
    required this.key,
    required this.label,
    required this.quantityMilliUnits,
    required this.revenue,
    required this.cost,
  });

  final String key;
  final String label;
  final int quantityMilliUnits;
  final Money revenue;
  final Money cost;

  Money get grossProfit => revenue - cost;
}

class SalesAnalytics {
  const SalesAnalytics({
    required this.from,
    required this.to,
    required this.salesRevenue,
    required this.salesCost,
    required this.salesCount,
    required this.paymentMethodCounts,
    required this.productRows,
    required this.categoryRows,
    required this.customerRows,
    required this.mayBeTruncated,
  });

  final DateTime from;
  final DateTime to;
  final Money salesRevenue;
  final Money salesCost;
  final int salesCount;
  final Map<String, int> paymentMethodCounts;
  final List<SalesAnalyticsRow> productRows;
  final List<SalesAnalyticsRow> categoryRows;
  final List<SalesAnalyticsRow> customerRows;
  final bool mayBeTruncated;

  Money get grossProfit => salesRevenue - salesCost;
}
