import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' as firebase_functions;

import '../../../../core/errors/failure.dart';
import '../../../../core/idempotency/idempotency_key.dart';
import '../../../../core/money/money.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../../infrastructure/firebase/firebase_paths.dart';
import '../../domain/entities/booking.dart';
import '../../domain/entities/booking_expense.dart';
import '../../domain/entities/booking_payment.dart';
import '../../domain/enums/booking_enums.dart';
import '../../domain/repositories/booking_repository.dart';

class FirestoreBookingRepository implements BookingRepository {
  FirestoreBookingRepository({
    required FirebaseFirestore firestore,
    required firebase_functions.FirebaseFunctions functions,
  })  : _firestore = firestore,
        _functions = functions;

  final FirebaseFirestore _firestore;
  final firebase_functions.FirebaseFunctions _functions;

  @override
  Stream<Result<List<Booking>>> watchBookings({
    required StoreContext context,
    DateTime? from,
    DateTime? to,
    BookingStatus? status,
  }) async* {
    try {
      await for (final snapshot in FirebasePaths.bookings(
        _firestore,
        context.storeId,
      ).snapshots()) {
        final bookings = snapshot.docs
            .map(_fromSnapshot)
            .where(
              (booking) =>
                  booking.storeId == context.storeId &&
                  _matches(booking, from: from, to: to, status: status),
            )
            .toList()
          ..sort((left, right) => left.startAt.compareTo(right.startAt));
        yield Success<List<Booking>>(bookings);
      }
    } on FirebaseException catch (error) {
      yield FailureResult<List<Booking>>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      yield FailureResult<List<Booking>>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<List<Booking>>> getBookings({
    required StoreContext context,
    DateTime? from,
    DateTime? to,
    BookingStatus? status,
  }) async {
    try {
      final snapshot = await FirebasePaths.bookings(
        _firestore,
        context.storeId,
      ).get();
      final bookings = snapshot.docs
          .map(_fromSnapshot)
          .where(
            (booking) =>
                booking.storeId == context.storeId &&
                _matches(booking, from: from, to: to, status: status),
          )
          .toList()
        ..sort((left, right) => left.startAt.compareTo(right.startAt));
      return Success<List<Booking>>(bookings);
    } on FirebaseException catch (error) {
      return FailureResult<List<Booking>>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<List<Booking>>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<Booking>> getBooking({
    required StoreContext context,
    required String bookingId,
  }) async {
    if (bookingId.trim().isEmpty || bookingId.contains('/')) {
      return const FailureResult<Booking>(
        ValidationFailure('Booking id is invalid.'),
      );
    }
    try {
      final snapshot = await FirebasePaths.booking(
        _firestore,
        context.storeId,
        bookingId,
      ).get();
      if (!snapshot.exists) {
        return const FailureResult<Booking>(
          ValidationFailure('Booking was not found.'),
        );
      }
      final booking = _fromSnapshot(snapshot);
      if (booking.storeId != context.storeId) {
        return const FailureResult<Booking>(
          AuthorizationFailure('Booking belongs to another store.'),
        );
      }
      return Success<Booking>(booking);
    } on FirebaseException catch (error) {
      return FailureResult<Booking>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<Booking>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<Booking>> createBooking({
    required StoreContext context,
    required Booking booking,
  }) async {
    if (booking.storeId != context.storeId) {
      return const FailureResult<Booking>(
        AuthorizationFailure('Booking does not belong to the active store.'),
      );
    }
    try {
      final response = await _functions
          .httpsCallable('createBooking')
          .call<Map<String, dynamic>>(_request(context, booking));
      if (response.data['bookingId'] != booking.id) {
        return const FailureResult<Booking>(
          InfrastructureFailure('The booking service returned another id.'),
        );
      }
      return await getBooking(context: context, bookingId: booking.id);
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      return FailureResult<Booking>(_mapFailure(error));
    } catch (error) {
      return FailureResult<Booking>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<Booking>> updateBooking({
    required StoreContext context,
    required Booking booking,
  }) async {
    if (booking.storeId != context.storeId) {
      return const FailureResult<Booking>(
        AuthorizationFailure('Booking does not belong to the active store.'),
      );
    }
    try {
      final response = await _functions
          .httpsCallable('updateBooking')
          .call<Map<String, dynamic>>(_request(context, booking));
      if (response.data['bookingId'] != booking.id) {
        return const FailureResult<Booking>(
          InfrastructureFailure('The booking update returned another id.'),
        );
      }
      return await getBooking(context: context, bookingId: booking.id);
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      return FailureResult<Booking>(_mapFailure(error));
    } catch (error) {
      return FailureResult<Booking>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<Booking>> transitionBooking({
    required StoreContext context,
    required String bookingId,
    required BookingStatus status,
  }) async {
    try {
      final response = await _functions
          .httpsCallable('transitionBooking')
          .call<Map<String, dynamic>>({
        'storeId': context.storeId,
        'bookingId': bookingId,
        'status': status.name,
      });
      if (response.data['bookingId'] != bookingId) {
        return const FailureResult<Booking>(
          InfrastructureFailure(
            'The booking status service returned another id.',
          ),
        );
      }
      return await getBooking(context: context, bookingId: bookingId);
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      return FailureResult<Booking>(_mapFailure(error));
    } catch (error) {
      return FailureResult<Booking>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<Booking>> addPayment({
    required StoreContext context,
    required String bookingId,
    required BookingPayment payment,
  }) async {
    return const FailureResult<Booking>(
      ValidationFailure(
        'Booking payment posting will be enabled with the accounting slice.',
      ),
    );
  }

  @override
  Future<Result<Booking>> addExpense({
    required StoreContext context,
    required String bookingId,
    required BookingExpense expense,
  }) async {
    return const FailureResult<Booking>(
      ValidationFailure(
        'Booking expense posting will be enabled with the accounting slice.',
      ),
    );
  }

  static bool _matches(
    Booking booking, {
    DateTime? from,
    DateTime? to,
    BookingStatus? status,
  }) {
    final startAt = booking.startAt;
    final normalizedFrom = from?.toUtc();
    final normalizedTo = to?.toUtc();
    return (status == null || booking.status == status) &&
        (normalizedFrom == null || !startAt.isBefore(normalizedFrom)) &&
        (normalizedTo == null || startAt.isBefore(normalizedTo));
  }

  Map<String, dynamic> _request(
    StoreContext context,
    Booking booking,
  ) {
    return <String, dynamic>{
      'storeId': context.storeId,
      'booking': <String, dynamic>{
        'id': booking.id,
        'idempotencyKey': booking.idempotencyKey.value,
        'customerId': booking.customerId,
        'photographyOptionId': booking.photographyOptionId,
        'startAt': booking.startAt.toIso8601String(),
        'durationMinutes': booking.durationMinutes,
        'location': booking.location,
        'notes': booking.notes,
        'totalPriceMinorUnits': booking.totalPrice.minorUnits,
        'totalDiscountMinorUnits': booking.totalDiscount.minorUnits,
        'depositAmountMinorUnits': booking.depositAmount.minorUnits,
      },
    };
  }

  static Booking _fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final currency = _string(data['currency'], fallback: 'ILS');
    return Booking(
      id: snapshot.id,
      storeId: _string(data['storeId']),
      idempotencyKey: IdempotencyKey(
        _string(data['idempotencyKey'], fallback: 'legacy-${snapshot.id}'),
      ),
      customerId: _string(data['customerId']),
      customerName: _string(data['customerName']),
      customerPhone: _string(data['customerPhone']),
      customerEmail: data['customerEmail'] as String?,
      startAt: _date(data['startAt']),
      durationMinutes: _int(data['durationMinutes']),
      location: _string(data['location']),
      notes: data['notes'] as String?,
      photographyOptionId: _string(data['photographyOptionId']),
      photographyOptionName: _string(data['photographyOptionName']),
      totalPrice: Money(
        minorUnits: _int(data['totalPriceMinorUnits']),
        currency: currency,
      ),
      depositAmount: Money(
        minorUnits: _int(data['depositAmountMinorUnits']),
        currency: currency,
      ),
      paidAmount: Money(
        minorUnits: _int(data['paidAmountMinorUnits']),
        currency: currency,
      ),
      status: _status(data['status']),
      paymentStatus: _paymentStatus(data['paymentStatus']),
      payments: _payments(data['payments'], currency),
      expenses: _expenses(data['expenses'], currency),
      totalDiscount: Money(
        minorUnits: _int(data['totalDiscountMinorUnits']),
        currency: currency,
      ),
      createdAt: _date(data['createdAt']),
      updatedAt: _optionalDate(data['updatedAt']),
    );
  }

  static List<BookingPayment> _payments(Object? value, String currency) {
    if (value is! List) {
      return const [];
    }
    return [
      for (final item in value)
        if (item is Map)
          BookingPayment(
            id: _string(item['id'], fallback: 'payment'),
            amount: Money(
              minorUnits: _int(item['amountMinorUnits']),
              currency: _string(item['currency'], fallback: currency),
            ),
            paidAt: _date(item['paidAt']),
            paymentMethod: _string(item['paymentMethod'], fallback: 'cash'),
            reference: item['reference'] as String?,
            notes: item['notes'] as String?,
          ),
    ];
  }

  static List<BookingExpense> _expenses(Object? value, String currency) {
    if (value is! List) {
      return const [];
    }
    return [
      for (final item in value)
        if (item is Map)
          BookingExpense(
            id: _string(item['id'], fallback: 'expense'),
            description: _string(item['description'], fallback: 'Expense'),
            amount: Money(
              minorUnits: _int(item['amountMinorUnits']),
              currency: _string(item['currency'], fallback: currency),
            ),
            expenseDate: _date(item['expenseDate']),
            expenseTypeId: item['expenseTypeId'] as String?,
          ),
    ];
  }

  static BookingStatus _status(Object? value) {
    return BookingStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => BookingStatus.pending,
    );
  }

  static BookingPaymentStatus _paymentStatus(Object? value) {
    return BookingPaymentStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => BookingPaymentStatus.unpaid,
    );
  }

  static String _string(Object? value, {String fallback = ''}) {
    return value is String ? value : fallback;
  }

  static int _int(Object? value) {
    return value is num ? value.toInt() : 0;
  }

  static DateTime _date(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  static DateTime? _optionalDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  static Failure _mapFailure(
    firebase_functions.FirebaseFunctionsException error,
  ) {
    switch (error.code) {
      case 'permission-denied':
        return AuthorizationFailure(
          error.message ?? 'Booking operation is not allowed.',
        );
      case 'failed-precondition':
        return ConflictFailure(
          error.message ?? 'Booking operation conflicts with current state.',
        );
      case 'invalid-argument':
      case 'not-found':
        return ValidationFailure(
          error.message ?? 'Booking data is invalid.',
        );
      default:
        return InfrastructureFailure(
          error.message ?? 'Booking operation failed.',
        );
    }
  }
}
