import 'dart:async';

import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/store_membership.dart';

abstract interface class StoreMembershipRepository {
  Future<Result<StoreMembership>> getMembership({
    required StoreContext context,
  });
}

/// Optional real-time membership contract used to revoke sessions immediately.
/// Implementations must return failure for missing, inactive or invalid members.
abstract interface class StoreMembershipWatcher {
  Stream<Result<StoreMembership>> watchMembership({
    required StoreContext context,
  });
}
