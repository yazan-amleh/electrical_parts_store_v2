import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/activity_log.dart';

class ActivityLogFirestoreMapper {
  static ActivityLog fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return ActivityLog(
      id: snapshot.id,
      storeId: data['storeId'] as String? ?? '',
      type: _type(data['type'] as String?),
      description:
          data['description'] as String? ?? data['message'] as String? ?? '',
      occurredAt: _date(data['timestamp'] ?? data['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      userId: data['userId'] as String?,
      userName: data['userName'] as String?,
      metadata: _metadata(data['metadata']),
    );
  }

  static ActivityType _type(String? value) {
    return ActivityType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => ActivityType.other,
    );
  }

  static DateTime? _date(Object? value) {
    if (value is Timestamp) {
      return value.toDate().toUtc();
    }
    if (value is DateTime) {
      return value.toUtc();
    }
    if (value is String) {
      return DateTime.tryParse(value)?.toUtc();
    }
    return null;
  }

  static Map<String, dynamic> _metadata(Object? value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const <String, dynamic>{};
  }
}
