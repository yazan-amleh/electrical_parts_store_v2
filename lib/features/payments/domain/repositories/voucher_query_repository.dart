import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/voucher_record.dart';

abstract interface class VoucherQueryRepository {
  Future<Result<VoucherPage>> getVoucherPage({
    required StoreContext context,
    VoucherCursor? after,
    int pageSize = 50,
  });
}
