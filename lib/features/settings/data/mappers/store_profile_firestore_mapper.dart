import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/store_profile.dart';

abstract final class StoreProfileFirestoreMapper {
  static StoreProfile fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return StoreProfile(
      id: snapshot.id,
      name: _string(data['name'], snapshot.id),
      currency: _string(data['currency'], 'ILS'),
      phone: _string(data['phone'], ''),
      address: _string(data['address'], ''),
    );
  }

  static String _string(Object? value, String fallback) {
    return value is String && value.trim().isNotEmpty ? value : fallback;
  }
}
