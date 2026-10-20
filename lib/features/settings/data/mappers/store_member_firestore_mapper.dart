import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../auth/domain/enums/store_role.dart';
import '../../domain/entities/store_member.dart';

abstract final class StoreMemberFirestoreMapper {
  static StoreMember fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final roleName = data['role'] is String ? data['role'] as String : '';
    return StoreMember(
      userId: snapshot.id,
      role: StoreRole.values.firstWhere(
        (role) => role.name == roleName,
        orElse: () => StoreRole.viewer,
      ),
      isActive: data['isActive'] is bool ? data['isActive'] as bool : true,
      displayName: _stringOrNull(data['displayName']),
      email: _stringOrNull(data['email']),
    );
  }

  static String? _stringOrNull(Object? value) {
    return value is String && value.trim().isNotEmpty ? value : null;
  }
}
