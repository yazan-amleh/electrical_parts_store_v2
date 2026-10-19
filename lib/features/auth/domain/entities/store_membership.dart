import '../enums/store_role.dart';

class StoreMembership {
  const StoreMembership({
    required this.storeId,
    required this.userId,
    required this.role,
    this.isActive = true,
  });

  final String storeId;
  final String userId;
  final StoreRole role;
  final bool isActive;

  bool get canAccessStore => isActive;
}
