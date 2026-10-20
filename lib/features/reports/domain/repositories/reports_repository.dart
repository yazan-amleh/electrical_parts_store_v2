import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/operational_report.dart';
import '../entities/sales_analytics.dart';

abstract interface class ReportsRepository {
  Future<Result<OperationalReport>> getOperationalReport({
    required StoreContext context,
    required DateTime from,
    required DateTime to,
    int limit = 500,
  });

  Future<Result<SalesAnalytics>> getSalesAnalytics({
    required StoreContext context,
    required DateTime from,
    required DateTime to,
    int limit = 500,
  });
}
