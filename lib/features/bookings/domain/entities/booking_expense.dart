import '../../../../core/money/money.dart';

class BookingExpense {
  BookingExpense({
    required this.id,
    required this.description,
    required this.amount,
    required this.expenseDate,
    this.expenseTypeId,
  }) {
    if (id.trim().isEmpty || id.contains('/')) {
      throw ArgumentError('Booking expense id is invalid.');
    }
    if (description.trim().isEmpty) {
      throw ArgumentError('Booking expense description is required.');
    }
    if (amount.isNegative || amount.isZero) {
      throw ArgumentError('Booking expense must be greater than zero.');
    }
  }

  final String id;
  final String description;
  final Money amount;
  final DateTime expenseDate;
  final String? expenseTypeId;
}
