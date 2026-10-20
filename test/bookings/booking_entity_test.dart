import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/core/idempotency/idempotency_key.dart';
import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/features/bookings/domain/entities/booking.dart';
import 'package:electrical_parts_store_v2/features/bookings/domain/entities/booking_expense.dart';
import 'package:electrical_parts_store_v2/features/bookings/domain/entities/booking_payment.dart';
import 'package:electrical_parts_store_v2/features/bookings/domain/enums/booking_enums.dart';

Booking _booking({
  int total = 10000,
  int deposit = 3000,
}) {
  final now = DateTime.utc(2026, 1, 1, 10);
  return Booking(
    id: 'booking-1',
    storeId: 'store-a',
    idempotencyKey: const IdempotencyKey('booking-key-1'),
    customerId: 'customer-1',
    customerName: 'Customer',
    customerPhone: '0590000000',
    startAt: now,
    durationMinutes: 120,
    location: 'Studio A',
    photographyOptionId: 'option-1',
    photographyOptionName: 'Session',
    totalPrice: Money(minorUnits: total),
    depositAmount: Money(minorUnits: deposit),
    paidAmount: Money.zero(),
    createdAt: now,
  );
}

void main() {
  test('calculates booking time and outstanding amount', () {
    final booking = _booking();
    expect(booking.endAt, DateTime.utc(2026, 1, 1, 12));
    expect(booking.outstanding.minorUnits, 10000);
    expect(booking.calculatedPaymentStatus, BookingPaymentStatus.unpaid);
  });

  test('accepts a payment without mutating the original booking', () {
    final booking = _booking();
    final paid = booking.withPayment(
      BookingPayment(
        id: 'payment-1',
        amount: Money(minorUnits: 3000),
        paidAt: DateTime.utc(2026, 1, 1, 9),
        paymentMethod: 'cash',
      ),
    );
    expect(booking.paidAmount.minorUnits, 0);
    expect(paid.paidAmount.minorUnits, 3000);
    expect(paid.payments, hasLength(1));
    expect(paid.calculatedPaymentStatus, BookingPaymentStatus.deposit);
  });

  test('rejects invalid status transitions and excess payments', () {
    expect(
      () => _booking().transitionTo(BookingStatus.completed),
      throwsStateError,
    );
    expect(
      () => _booking().withPayment(
        BookingPayment(
          id: 'payment-1',
          amount: Money(minorUnits: 11000),
          paidAt: DateTime.utc(2026, 1, 1, 9),
          paymentMethod: 'cash',
        ),
      ),
      throwsArgumentError,
    );
  });

  test('sums expenses in the booking currency', () {
    final booking = _booking().withExpense(
      BookingExpense(
        id: 'expense-1',
        description: 'Transport',
        amount: Money(minorUnits: 500),
        expenseDate: DateTime.utc(2026, 1, 1),
      ),
    );
    expect(booking.totalExpenses.minorUnits, 500);
  });
}
