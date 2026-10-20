import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/repair_payment.dart';
import '../entities/repair_posting_accounts.dart';
import '../entities/repair_request.dart';
import '../enums/repair_status.dart';

abstract interface class RepairRepository {
  Future<Result<List<RepairRequest>>> getRepairs({
    required StoreContext context,
    RepairStatus? status,
  });

  Future<Result<RepairRequest>> getRepair({
    required StoreContext context,
    required String repairId,
  });

  Future<Result<RepairRequest>> createRepair({
    required StoreContext context,
    required RepairRequest repair,
  });

  Future<Result<RepairRequest>> updateRepair({
    required StoreContext context,
    required RepairRequest repair,
  });

  Future<Result<RepairRequest>> deliverRepair({
    required StoreContext context,
    required String repairId,
    required String idempotencyKey,
    required DateTime postedAt,
    required RepairPostingAccounts accounts,
  });

  Future<Result<RepairPayment>> postPayment({
    required StoreContext context,
    required RepairPayment payment,
    required RepairPostingAccounts accounts,
  });

  Future<Result<List<RepairPayment>>> getPayments({
    required StoreContext context,
    required String repairId,
  });
}
