import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/cheque.dart';
import '../entities/cheque_settlement_request.dart';
import '../entities/cheque_settlement_result.dart';
import '../enums/cheque_status.dart';

abstract interface class ChequeRepository {
  Future<Result<List<Cheque>>> getCheques({
    required StoreContext context,
    ChequeStatus? status,
  });

  Future<Result<ChequeSettlementResult>> settleCheque({
    required StoreContext context,
    required ChequeSettlementRequest request,
  });
}
