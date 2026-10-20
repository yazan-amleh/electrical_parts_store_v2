import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/accounting_audit_report.dart';

abstract interface class AccountingAuditRepository {
  Future<Result<AccountingAuditReport>> runAudit({
    required StoreContext context,
  });
}
