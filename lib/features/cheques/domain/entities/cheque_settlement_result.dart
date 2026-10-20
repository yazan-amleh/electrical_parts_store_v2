import '../enums/cheque_status.dart';

class ChequeSettlementResult {
  const ChequeSettlementResult({
    required this.chequeId,
    required this.status,
    required this.journalEntryId,
  });

  final String chequeId;
  final ChequeStatus status;
  final String journalEntryId;
}
