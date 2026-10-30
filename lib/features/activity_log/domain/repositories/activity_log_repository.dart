import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/activity_log.dart';

abstract interface class ActivityLogRepository {
  Stream<Result<List<ActivityLog>>> watchLogs({
    required StoreContext context,
    int limit = 100,
    DateTime? fromInclusive,
    DateTime? toExclusive,
  });
}
