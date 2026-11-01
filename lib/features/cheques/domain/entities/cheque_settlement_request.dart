import '../../../../core/idempotency/idempotency_key.dart';
import '../enums/cheque_settlement_action.dart';

class ChequeSettlementRequest {
  ChequeSettlementRequest({
    required this.chequeId,
    required this.action,
    required this.idempotencyKey,
    required DateTime postedAt,
    this.bankAccountId,
  }) : postedAt = postedAt.toUtc() {
    if (chequeId.trim().isEmpty || chequeId.contains('/')) {
      throw ArgumentError('Cheque id is invalid.');
    }
    if (idempotencyKey.value.contains('/')) {
      throw ArgumentError(
        'Cheque settlement idempotency key cannot contain a slash.',
      );
    }
    if (action == ChequeSettlementAction.clear &&
        (bankAccountId == null || bankAccountId!.trim().isEmpty)) {
      throw ArgumentError('A bank account is required to clear a cheque.');
    }
    if (bankAccountId?.contains('/') == true) {
      throw ArgumentError('Bank account id cannot contain a slash.');
    }
  }

  final String chequeId;
  final ChequeSettlementAction action;
  final IdempotencyKey idempotencyKey;
  final DateTime postedAt;
  final String? bankAccountId;
}
