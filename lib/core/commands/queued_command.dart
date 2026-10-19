enum QueuedCommandStatus {
  pending,
  processing,
  completed,
  failed,
}

class QueuedCommand {
  QueuedCommand({
    required this.id,
    required this.storeId,
    required this.createdBy,
    required this.operation,
    required this.idempotencyKey,
    required Map<String, dynamic> payload,
    required DateTime createdAt,
    this.status = QueuedCommandStatus.pending,
    this.attemptCount = 0,
    DateTime? nextAttemptAt,
    DateTime? leaseUntil,
    this.lastError,
  })  : payload = Map.unmodifiable(Map<String, dynamic>.from(payload)),
        createdAt = createdAt.toUtc(),
        nextAttemptAt = nextAttemptAt?.toUtc(),
        leaseUntil = leaseUntil?.toUtc() {
    _ensureSafeIdentifier(id, 'Queued command id');
    _ensureSafeIdentifier(storeId, 'Queued command store id');
    _ensureSafeIdentifier(createdBy, 'Queued command creator');
    if (operation.trim().isEmpty) {
      throw ArgumentError('Queued command operation is required.');
    }
    if (idempotencyKey.trim().isEmpty || idempotencyKey.contains('/')) {
      throw ArgumentError('Queued command idempotency key is invalid.');
    }
    if (attemptCount < 0) {
      throw ArgumentError('Queued command attempt count cannot be negative.');
    }
  }

  final String id;
  final String storeId;
  final String createdBy;
  final String operation;
  final String idempotencyKey;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final QueuedCommandStatus status;
  final int attemptCount;
  final DateTime? nextAttemptAt;
  final DateTime? leaseUntil;
  final String? lastError;

  bool isDue(DateTime now) {
    final currentTime = now.toUtc();
    if (status == QueuedCommandStatus.processing) {
      return leaseUntil == null || !leaseUntil.isAfter(currentTime);
    }
    if (status != QueuedCommandStatus.pending) {
      return false;
    }
    final retryAt = nextAttemptAt;
    return retryAt == null || !retryAt.isAfter(currentTime);
  }

  QueuedCommand processing({DateTime? now}) {
    return _copy(
      status: QueuedCommandStatus.processing,
      attemptCount: attemptCount + 1,
      nextAttemptAt: null,
      leaseUntil:
          (now ?? DateTime.now()).toUtc().add(const Duration(minutes: 5)),
      lastError: null,
    );
  }

  QueuedCommand completed() {
    return _copy(
      status: QueuedCommandStatus.completed,
      nextAttemptAt: null,
      leaseUntil: null,
      lastError: null,
    );
  }

  QueuedCommand retryAt(DateTime retryAt, String error) {
    return _copy(
      status: QueuedCommandStatus.pending,
      nextAttemptAt: retryAt,
      leaseUntil: null,
      lastError: error,
    );
  }

  QueuedCommand failed(String error) {
    return _copy(
      status: QueuedCommandStatus.failed,
      nextAttemptAt: null,
      leaseUntil: null,
      lastError: error,
    );
  }

  QueuedCommand _copy({
    required QueuedCommandStatus status,
    int? attemptCount,
    DateTime? nextAttemptAt,
    DateTime? leaseUntil,
    String? lastError,
  }) {
    return QueuedCommand(
      id: id,
      storeId: storeId,
      createdBy: createdBy,
      operation: operation,
      idempotencyKey: idempotencyKey,
      payload: payload,
      createdAt: createdAt,
      status: status,
      attemptCount: attemptCount ?? this.attemptCount,
      nextAttemptAt: nextAttemptAt,
      leaseUntil: leaseUntil,
      lastError: lastError,
    );
  }

  static void _ensureSafeIdentifier(String value, String label) {
    if (value.trim().isEmpty) {
      throw ArgumentError('$label is required.');
    }
    if (value.contains('/')) {
      throw ArgumentError('$label cannot contain a slash.');
    }
  }
}
