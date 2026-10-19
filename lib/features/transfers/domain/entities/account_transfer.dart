import '../../../../core/idempotency/idempotency_key.dart';
import '../../../../core/money/money.dart';
import '../../../../core/tenancy/store_context.dart';

class AccountTransfer {
  AccountTransfer({
    required this.id,
    required this.storeId,
    required this.idempotencyKey,
    required DateTime postedAt,
    required this.fromAccountId,
    required this.toAccountId,
    required this.amount,
    this.description,
  }) : postedAt = postedAt.toUtc() {
    _ensureSafeIdentifier(id, 'Account transfer id');
    _ensureSafeIdentifier(storeId, 'Store id');
    _ensureSafeIdentifier(fromAccountId, 'Source account id');
    _ensureSafeIdentifier(toAccountId, 'Destination account id');

    if (fromAccountId == toAccountId) {
      throw ArgumentError(
        'Source and destination accounts must be different.',
      );
    }
    if (idempotencyKey.value.contains('/')) {
      throw ArgumentError(
        'Account transfer idempotency key cannot contain a slash.',
      );
    }
    if (amount.isNegative || amount.isZero) {
      throw ArgumentError(
        'Account transfer amount must be greater than zero.',
      );
    }
  }

  final String id;
  final String storeId;
  final IdempotencyKey idempotencyKey;
  final DateTime postedAt;
  final String fromAccountId;
  final String toAccountId;
  final Money amount;
  final String? description;

  String get sourceType => 'accountTransfer';

  StoreContext contextFor(String userId) {
    return StoreContext(storeId: storeId, userId: userId);
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
