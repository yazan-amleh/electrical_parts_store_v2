import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/store_membership.dart';

abstract interface class StoreMembershipRepository {
  Future<Result<StoreMembership>> getMembership({
    required StoreContext context,
  });
}
