import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/operational_report.dart';

abstract interface class ReportsRepository {
  Future<Result<OperationalReport>> getOperationalReport({
    required StoreContext context,
    required DateTime from,
    required DateTime to,
    int limit = 500,
  });
}
