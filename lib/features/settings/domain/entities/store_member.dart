import '../../../auth/domain/enums/store_role.dart';

class StoreMember {
  const StoreMember({
    required this.userId,
    required this.role,
    required this.isActive,
    this.displayName,
    this.email,
  });

  final String userId;
  final StoreRole role;
  final bool isActive;
  final String? displayName;
  final String? email;

  StoreMember copyWith({
    StoreRole? role,
    bool? isActive,
  }) {
    return StoreMember(
      userId: userId,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      displayName: displayName,
      email: email,
    );
  }
}
