import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/store_membership.dart';
import '../../domain/enums/store_role.dart';

abstract final class StoreMembershipFirestoreMapper {
  static StoreMembership fromSnapshot({
    required DocumentSnapshot<Map<String, dynamic>> snapshot,
    required String storeId,
    required String userId,
  }) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final roleName = data['role'] is String ? data['role'] as String : '';

    return StoreMembership(
      storeId: storeId,
      userId: userId,
      role: StoreRole.values.firstWhere(
        (role) => role.name == roleName,
        orElse: () => StoreRole.viewer,
      ),
      isActive: data['isActive'] is bool ? data['isActive'] as bool : true,
    );
  }
}
