import '../../../../core/idempotency/idempotency_key.dart';
import '../../../../core/money/money.dart';
import '../enums/booking_enums.dart';
import 'booking_expense.dart';
import 'booking_payment.dart';

class Booking {
  Booking({
    required this.id,
    required this.storeId,
    required this.idempotencyKey,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required DateTime startAt,
    required this.durationMinutes,
    required this.location,
    required this.photographyOptionId,
    required this.photographyOptionName,
    required this.totalPrice,
    required this.depositAmount,
    required this.paidAmount,
    required DateTime createdAt,
    this.customerEmail,
    this.notes,
    this.status = BookingStatus.pending,
    this.paymentStatus = BookingPaymentStatus.unpaid,
    List<BookingPayment> payments = const [],
    List<BookingExpense> expenses = const [],
    this.totalDiscount = const Money.zero(),
    DateTime? updatedAt,
  })  : startAt = startAt.toUtc(),
        createdAt = createdAt.toUtc(),
        updatedAt = updatedAt?.toUtc(),
        payments = List.unmodifiable(payments),
        expenses = List.unmodifiable(expenses) {
    _ensureIdentifier(id, 'Booking id');
    _ensureIdentifier(storeId, 'Store id');
    _ensureIdentifier(customerId, 'Booking customer id');
    if (idempotencyKey.value.contains('/')) {
      throw ArgumentError('Booking idempotency key cannot contain a slash.');
    }
    if (customerName.trim().isEmpty || customerPhone.trim().isEmpty) {
      throw ArgumentError('Booking customer name and phone are required.');
    }
    if (durationMinutes <= 0) {
      throw ArgumentError('Booking duration must be greater than zero.');
    }
    if (location.trim().isEmpty) {
      throw ArgumentError('Booking location is required.');
    }
    _ensureIdentifier(photographyOptionId, 'Photography option id');
    if (photographyOptionName.trim().isEmpty) {
      throw ArgumentError('Photography option name is required.');
    }
    if (totalPrice.isNegative ||
        depositAmount.isNegative ||
        paidAmount.isNegative ||
        totalDiscount.isNegative) {
      throw ArgumentError('Booking amounts cannot be negative.');
    }
    if (depositAmount.minorUnits > totalPrice.minorUnits ||
        paidAmount.minorUnits > totalPrice.minorUnits) {
      throw ArgumentError('Booking payments cannot exceed the booking total.');
    }
    for (final amount in <Money>[
      depositAmount,
      paidAmount,
      totalDiscount,
      for (final payment in this.payments) payment.amount,
      for (final expense in this.expenses) expense.amount,
    ]) {
      if (amount.currency != totalPrice.currency) {
        throw ArgumentError('Booking amounts must use one currency.');
      }
    }
  }

  final String id;
  final String storeId;
  final IdempotencyKey idempotencyKey;
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String? customerEmail;
  final DateTime startAt;
  final int durationMinutes;
  final String location;
  final String? notes;
  final String photographyOptionId;
  final String photographyOptionName;
  final Money totalPrice;
  final Money depositAmount;
  final Money paidAmount;
  final BookingStatus status;
  final BookingPaymentStatus paymentStatus;
  final List<BookingPayment> payments;
  final List<BookingExpense> expenses;
  final Money totalDiscount;
  final DateTime createdAt;
  final DateTime? updatedAt;

  DateTime get endAt => startAt.add(Duration(minutes: durationMinutes));

  Money get totalExpenses => expenses.fold(
        Money.zero(currency: totalPrice.currency),
        (total, expense) => total + expense.amount,
      );

  Money get outstanding {
    final amount = totalPrice.minorUnits - paidAmount.minorUnits;
    return Money(
      minorUnits: amount < 0 ? 0 : amount,
      currency: totalPrice.currency,
    );
  }

  BookingPaymentStatus get calculatedPaymentStatus {
    if (paidAmount.isZero) {
      return BookingPaymentStatus.unpaid;
    }
    if (paidAmount.minorUnits >= totalPrice.minorUnits) {
      return BookingPaymentStatus.fullyPaid;
    }
    if (depositAmount.minorUnits > 0 &&
        paidAmount.minorUnits >= depositAmount.minorUnits) {
      return BookingPaymentStatus.deposit;
    }
    return BookingPaymentStatus.partialPaid;
  }

  Booking withPayment(BookingPayment payment) {
    final nextPaid = paidAmount + payment.amount;
    if (nextPaid.minorUnits > totalPrice.minorUnits) {
      throw ArgumentError('Booking payment exceeds the outstanding amount.');
    }
    return copyWith(
      paidAmount: nextPaid,
      paymentStatus: _paymentStatusFor(
        nextPaid,
        total: totalPrice,
        deposit: depositAmount,
      ),
      payments: [...payments, payment],
      updatedAt: DateTime.now().toUtc(),
    );
  }

  Booking withExpense(BookingExpense expense) {
    return copyWith(
      expenses: [...expenses, expense],
      updatedAt: DateTime.now().toUtc(),
    );
  }

  Booking transitionTo(BookingStatus nextStatus) {
    if (!_allowedTransitions[status]!.contains(nextStatus)) {
      throw StateError(
        'Invalid booking status transition: $status -> $nextStatus',
      );
    }
    return copyWith(status: nextStatus, updatedAt: DateTime.now().toUtc());
  }

  Booking copyWith({
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    DateTime? startAt,
    int? durationMinutes,
    String? location,
    String? notes,
    String? photographyOptionName,
    Money? totalPrice,
    Money? depositAmount,
    Money? paidAmount,
    BookingStatus? status,
    BookingPaymentStatus? paymentStatus,
    List<BookingPayment>? payments,
    List<BookingExpense>? expenses,
    Money? totalDiscount,
    DateTime? updatedAt,
  }) {
    return Booking(
      id: id,
      storeId: storeId,
      idempotencyKey: idempotencyKey,
      customerId: customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerEmail: customerEmail ?? this.customerEmail,
      startAt: startAt ?? this.startAt,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      location: location ?? this.location,
      notes: notes ?? this.notes,
      photographyOptionId: photographyOptionId,
      photographyOptionName:
          photographyOptionName ?? this.photographyOptionName,
      totalPrice: totalPrice ?? this.totalPrice,
      depositAmount: depositAmount ?? this.depositAmount,
      paidAmount: paidAmount ?? this.paidAmount,
      status: status ?? this.status,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      payments: payments ?? this.payments,
      expenses: expenses ?? this.expenses,
      totalDiscount: totalDiscount ?? this.totalDiscount,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static const _allowedTransitions = <BookingStatus, Set<BookingStatus>>{
    BookingStatus.pending: {
      BookingStatus.confirmed,
      BookingStatus.cancelled,
    },
    BookingStatus.confirmed: {
      BookingStatus.completed,
      BookingStatus.cancelled,
    },
    BookingStatus.completed: <BookingStatus>{},
    BookingStatus.cancelled: <BookingStatus>{},
  };

  static BookingPaymentStatus _paymentStatusFor(
    Money paid, {
    required Money total,
    required Money deposit,
  }) {
    if (paid.isZero) {
      return BookingPaymentStatus.unpaid;
    }
    if (paid.minorUnits >= total.minorUnits) {
      return BookingPaymentStatus.fullyPaid;
    }
    if (deposit.minorUnits > 0 && paid.minorUnits >= deposit.minorUnits) {
      return BookingPaymentStatus.deposit;
    }
    return BookingPaymentStatus.partialPaid;
  }

  static void _ensureIdentifier(String value, String label) {
    if (value.trim().isEmpty || value.contains('/')) {
      throw ArgumentError('$label is invalid.');
    }
  }
}
