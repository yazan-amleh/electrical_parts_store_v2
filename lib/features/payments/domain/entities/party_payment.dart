import '../../../../core/idempotency/idempotency_key.dart';
import '../../../../core/money/money.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../parties/domain/enums/party_type.dart';
import '../enums/party_payment_method.dart';

class PartyPayment {
  PartyPayment({
    required this.id,
    required this.storeId,
    required this.idempotencyKey,
    required DateTime postedAt,
    required this.partyType,
    required this.partyId,
    required this.paymentMethod,
    required this.amount,
    this.description,
    this.chequeNumber,
    this.bankName,
    this.dueDate,
  })  : postedAt = postedAt.toUtc(),
        dueDate = dueDate?.toUtc() {
    _ensureSafeIdentifier(id, 'Party payment id');
    _ensureSafeIdentifier(storeId, 'Store id');
    _ensureSafeIdentifier(partyId, 'Party id');

    if (idempotencyKey.value.contains('/')) {
      throw ArgumentError(
        'Party payment idempotency key cannot contain a slash.',
      );
    }
    if (amount.isNegative || amount.isZero) {
      throw ArgumentError('Party payment amount must be greater than zero.');
    }
    if (amount.currency.trim().isEmpty) {
      throw ArgumentError('Party payment currency is required.');
    }
    if (paymentMethod == PartyPaymentMethod.cheque) {
      if (partyType != PartyType.customer) {
        throw ArgumentError('Cheques are currently supported for customers.');
      }
      if (chequeNumber == null || chequeNumber.trim().isEmpty) {
        throw ArgumentError('A cheque number is required.');
      }
    }
  }

  final String id;
  final String storeId;
  final IdempotencyKey idempotencyKey;
  final DateTime postedAt;
  final PartyType partyType;
  final String partyId;
  final PartyPaymentMethod paymentMethod;
  final Money amount;
  final String? description;
  final String? chequeNumber;
  final String? bankName;
  final DateTime? dueDate;

  StoreContext contextFor(String userId) {
    return StoreContext(storeId: storeId, userId: userId);
  }

  String get sourceType {
    return partyType == PartyType.customer
        ? 'customerReceipt'
        : 'supplierPayment';
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
