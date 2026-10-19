import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/commands/queued_command.dart';

abstract final class QueuedCommandFirestoreMapper {
  static Map<String, dynamic> toMap(QueuedCommand command) {
    return <String, dynamic>{
      'storeId': command.storeId,
      'createdBy': command.createdBy,
      'operation': command.operation,
      'idempotencyKey': command.idempotencyKey,
      'payload': command.payload,
      'status': command.status.name,
      'attemptCount': command.attemptCount,
      'createdAt': Timestamp.fromDate(command.createdAt),
      'nextAttemptAt': command.nextAttemptAt == null
          ? null
          : Timestamp.fromDate(command.nextAttemptAt!),
      'leaseUntil': command.leaseUntil == null
          ? null
          : Timestamp.fromDate(command.leaseUntil!),
      'lastError': command.lastError,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static QueuedCommand fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final statusName = _string(
      data['status'],
      QueuedCommandStatus.pending.name,
    );
    final status = QueuedCommandStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => QueuedCommandStatus.pending,
    );
    final rawPayload = data['payload'];
    final payload = rawPayload is Map
        ? Map<String, dynamic>.from(rawPayload)
        : <String, dynamic>{};

    return QueuedCommand(
      id: snapshot.id,
      storeId: _string(data['storeId'], ''),
      createdBy: _string(data['createdBy'], ''),
      operation: _string(data['operation'], ''),
      idempotencyKey: _string(data['idempotencyKey'], snapshot.id),
      payload: payload,
      createdAt: _date(data['createdAt']) ?? DateTime.now().toUtc(),
      status: status,
      attemptCount: _int(data['attemptCount']),
      nextAttemptAt: _date(data['nextAttemptAt']),
      leaseUntil: _date(data['leaseUntil']),
      lastError: data['lastError'] as String?,
    );
  }

  static DateTime? _date(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }

  static String _string(Object? value, String fallback) {
    return value is String && value.isNotEmpty ? value : fallback;
  }

  static int _int(Object? value) {
    return value is int
        ? value
        : value is num
            ? value.toInt()
            : 0;
  }
}
