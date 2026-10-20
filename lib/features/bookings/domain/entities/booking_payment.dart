import '../../../../core/money/money.dart';

class BookingPayment {
  BookingPayment({
    required this.id,
    required this.amount,
    required this.paidAt,
    required this.paymentMethod,
    this.reference,
    this.notes,
  }) {
    if (id.trim().isEmpty || id.contains('/')) {
      throw ArgumentError('Booking payment id is invalid.');
    }
    if (amount.isNegative || amount.isZero) {
      throw ArgumentError('Booking payment must be greater than zero.');
    }
    if (paymentMethod.trim().isEmpty) {
      throw ArgumentError('Booking payment method is required.');
    }
  }

  final String id;
  final Money amount;
  final DateTime paidAt;
  final String paymentMethod;
  final String? reference;
  final String? notes;
}
