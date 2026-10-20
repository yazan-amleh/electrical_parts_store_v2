import '../../../../core/idempotency/idempotency_key.dart';
import '../../../../core/money/money.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../payments/domain/enums/party_payment_method.dart';
import '../enums/repair_payment_kind.dart';

class RepairPayment {
  RepairPayment({
    required this.id,
    required this.storeId,
    required this.repairId,
    required this.customerId,
    required this.idempotencyKey,
    required DateTime postedAt,
    required this.kind,
    required this.paymentMethod,
    required this.amount,
    this.description,
    this.chequeNumber,
    this.bankName,
    this.dueDate,
  })  : postedAt = postedAt.toUtc(),
        dueDate = dueDate?.toUtc() {
    _ensureIdentifier(id, 'Repair payment id');
    _ensureIdentifier(storeId, 'Repair payment store id');
    _ensureIdentifier(repairId, 'Repair id');
    _ensureIdentifier(customerId, 'Repair customer id');
    if (idempotencyKey.value.contains('/')) {
      throw ArgumentError(
        'Repair payment idempotency key cannot contain a slash.',
      );
    }
    if (amount.isNegative || amount.isZero) {
      throw ArgumentError('Repair payment amount must be greater than zero.');
    }
    if (kind == RepairPaymentKind.advance &&
        paymentMethod == PartyPaymentMethod.cheque) {
      throw ArgumentError('Cheque advances need a posted customer invoice.');
    }
    if (paymentMethod == PartyPaymentMethod.cheque) {
      if (chequeNumber == null || chequeNumber!.trim().isEmpty) {
        throw ArgumentError('A cheque number is required.');
      }
      if (bankName == null || bankName!.trim().isEmpty) {
        throw ArgumentError('A cheque bank name is required.');
      }
    }
  }

  final String id;
  final String storeId;
  final String repairId;
  final String customerId;
  final IdempotencyKey idempotencyKey;
  final DateTime postedAt;
  final RepairPaymentKind kind;
  final PartyPaymentMethod paymentMethod;
  final Money amount;
  final String? description;
  final String? chequeNumber;
  final String? bankName;
  final DateTime? dueDate;
}
