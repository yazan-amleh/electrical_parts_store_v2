import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';

abstract interface class NotificationRepository {
  Future<Result<void>> registerCurrentDevice({
    required StoreContext context,
  });

  Future<Result<void>> unregisterCurrentDevice({
    required StoreContext context,
  });
}
