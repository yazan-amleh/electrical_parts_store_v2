import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/store_member.dart';
import '../entities/store_profile.dart';

abstract interface class SettingsRepository {
  Future<Result<StoreProfile>> getStoreProfile({
    required StoreContext context,
  });

  Future<Result<List<StoreMember>>> getMembers({
    required StoreContext context,
  });

  Future<Result<void>> updateStoreProfile({
    required StoreContext context,
    required StoreProfile profile,
  });

  Future<Result<void>> updateMember({
    required StoreContext context,
    required StoreMember member,
  });

  Future<Result<void>> addMember({
    required StoreContext context,
    required StoreMember member,
  });
}
