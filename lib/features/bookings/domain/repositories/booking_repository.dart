import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/booking.dart';
import '../entities/booking_expense.dart';
import '../entities/booking_payment.dart';
import '../enums/booking_enums.dart';

abstract interface class BookingRepository {
  Stream<Result<List<Booking>>> watchBookings({
    required StoreContext context,
    DateTime? from,
    DateTime? to,
    BookingStatus? status,
  });

  Future<Result<List<Booking>>> getBookings({
    required StoreContext context,
    DateTime? from,
    DateTime? to,
    BookingStatus? status,
  });

  Future<Result<Booking>> getBooking({
    required StoreContext context,
    required String bookingId,
  });

  Future<Result<Booking>> createBooking({
    required StoreContext context,
    required Booking booking,
  });

  Future<Result<Booking>> updateBooking({
    required StoreContext context,
    required Booking booking,
  });

  Future<Result<Booking>> transitionBooking({
    required StoreContext context,
    required String bookingId,
    required BookingStatus status,
  });

  Future<Result<Booking>> addPayment({
    required StoreContext context,
    required String bookingId,
    required BookingPayment payment,
  });

  Future<Result<Booking>> addExpense({
    required StoreContext context,
    required String bookingId,
    required BookingExpense expense,
  });
}
