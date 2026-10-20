import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/booking_customer.dart';
import '../entities/photography_option.dart';

abstract interface class BookingCatalogRepository {
  Stream<Result<List<BookingCustomer>>> watchCustomers({
    required StoreContext context,
  });

  Stream<Result<List<PhotographyOption>>> watchOptions({
    required StoreContext context,
    bool activeOnly = true,
  });

  Future<Result<BookingCustomer>> saveCustomer({
    required StoreContext context,
    required BookingCustomer customer,
  });

  Future<Result<PhotographyOption>> saveOption({
    required StoreContext context,
    required PhotographyOption option,
  });
}
