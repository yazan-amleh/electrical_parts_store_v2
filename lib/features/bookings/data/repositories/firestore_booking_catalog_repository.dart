import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/money/money.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../../infrastructure/firebase/firebase_paths.dart';
import '../../domain/entities/booking_customer.dart';
import '../../domain/entities/photography_option.dart';
import '../../domain/repositories/booking_catalog_repository.dart';

class FirestoreBookingCatalogRepository implements BookingCatalogRepository {
  FirestoreBookingCatalogRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  @override
  Stream<Result<List<BookingCustomer>>> watchCustomers({
    required StoreContext context,
  }) async* {
    try {
      await for (final snapshot in FirebasePaths.bookingCustomers(
        _firestore,
        context.storeId,
      ).orderBy('name').snapshots()) {
        final customers = snapshot.docs
            .map(_customerFromSnapshot)
            .where((customer) => customer.storeId == context.storeId)
            .toList();
        yield Success<List<BookingCustomer>>(customers);
      }
    } on FirebaseException catch (error) {
      yield FailureResult<List<BookingCustomer>>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      yield FailureResult<List<BookingCustomer>>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Stream<Result<List<PhotographyOption>>> watchOptions({
    required StoreContext context,
    bool activeOnly = true,
  }) async* {
    try {
      Query<Map<String, dynamic>> query = FirebasePaths.photographyOptions(
        _firestore,
        context.storeId,
      );
      if (activeOnly) {
        query = query.where('isActive', isEqualTo: true);
      }
      await for (final snapshot in query.snapshots()) {
        final options = snapshot.docs
            .map(_optionFromSnapshot)
            .where((option) => option.storeId == context.storeId)
            .toList()
          ..sort((left, right) => left.name.compareTo(right.name));
        yield Success<List<PhotographyOption>>(options);
      }
    } on FirebaseException catch (error) {
      yield FailureResult<List<PhotographyOption>>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      yield FailureResult<List<PhotographyOption>>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<BookingCustomer>> saveCustomer({
    required StoreContext context,
    required BookingCustomer customer,
  }) async {
    if (customer.storeId != context.storeId) {
      return const FailureResult<BookingCustomer>(
        AuthorizationFailure('Booking customer belongs to another store.'),
      );
    }
    try {
      await FirebasePaths.bookingCustomer(
        _firestore,
        context.storeId,
        customer.id,
      ).set(_customerToMap(customer));
      return Success<BookingCustomer>(customer);
    } on FirebaseException catch (error) {
      return FailureResult<BookingCustomer>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<BookingCustomer>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<PhotographyOption>> saveOption({
    required StoreContext context,
    required PhotographyOption option,
  }) async {
    if (option.storeId != context.storeId) {
      return const FailureResult<PhotographyOption>(
        AuthorizationFailure('Photography option belongs to another store.'),
      );
    }
    try {
      await FirebasePaths.photographyOption(
        _firestore,
        context.storeId,
        option.id,
      ).set(_optionToMap(option));
      return Success<PhotographyOption>(option);
    } on FirebaseException catch (error) {
      return FailureResult<PhotographyOption>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<PhotographyOption>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  static BookingCustomer _customerFromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return BookingCustomer(
      id: snapshot.id,
      storeId: _string(data['storeId']),
      name: _string(data['name']),
      phoneNumber: _string(data['phoneNumber']),
      email: data['email'] as String?,
      address: data['address'] as String?,
      notes: data['notes'] as String?,
      createdAt: _date(data['createdAt']),
      updatedAt: _optionalDate(data['updatedAt']),
    );
  }

  static PhotographyOption _optionFromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return PhotographyOption(
      id: snapshot.id,
      storeId: _string(data['storeId']),
      name: _string(data['name']),
      description: data['description'] as String? ?? '',
      price: Money(
        minorUnits: _int(data['priceMinorUnits']),
        currency: _string(data['currency'], fallback: 'ILS'),
      ),
      durationMinutes: _int(data['durationMinutes']),
      isActive: data['isActive'] is bool ? data['isActive'] as bool : true,
      createdAt: _date(data['createdAt']),
      updatedAt: _optionalDate(data['updatedAt']),
    );
  }

  static Map<String, dynamic> _customerToMap(BookingCustomer customer) {
    return <String, dynamic>{
      'storeId': customer.storeId,
      'name': customer.name.trim(),
      'phoneNumber': customer.phoneNumber.trim(),
      'email': customer.email,
      'address': customer.address,
      'notes': customer.notes,
      'createdAt': Timestamp.fromDate(customer.createdAt),
      'updatedAt': customer.updatedAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(customer.updatedAt!),
    };
  }

  static Map<String, dynamic> _optionToMap(PhotographyOption option) {
    return <String, dynamic>{
      'storeId': option.storeId,
      'name': option.name.trim(),
      'description': option.description,
      'priceMinorUnits': option.price.minorUnits,
      'currency': option.price.currency,
      'durationMinutes': option.durationMinutes,
      'isActive': option.isActive,
      'createdAt': Timestamp.fromDate(option.createdAt),
      'updatedAt': option.updatedAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(option.updatedAt!),
    };
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
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  static DateTime? _optionalDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }
}
