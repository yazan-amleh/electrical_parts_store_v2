import '../../../../core/money/money.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../parties/domain/enums/party_type.dart';
import '../enums/cheque_status.dart';

class Cheque {
  Cheque({
    required this.id,
    required this.storeId,
    required this.partyType,
    required this.partyId,
    required this.amount,
    required this.chequeNumber,
    required this.bankName,
    required DateTime receivedAt,
    required this.status,
    this.dueDate,
    this.description,
    this.journalEntryId,
    this.settlementJournalEntryId,
  }) : receivedAt = receivedAt.toUtc() {
    _ensureIdentifier(id, 'Cheque id');
    _ensureIdentifier(storeId, 'Cheque store id');
    _ensureIdentifier(partyId, 'Cheque party id');
    if (partyType != PartyType.customer && partyType != PartyType.supplier) {
      throw ArgumentError('Only customer and supplier cheques are supported.');
    }
    if (amount.isNegative || amount.isZero) {
      throw ArgumentError('Cheque amount must be greater than zero.');
    }
    if (chequeNumber.trim().isEmpty) {
      throw ArgumentError('Cheque number is required.');
    }
    if (bankName.trim().isEmpty) {
      throw ArgumentError('Cheque bank name is required.');
    }
    if (status != ChequeStatus.pending &&
        (settlementJournalEntryId == null ||
            settlementJournalEntryId!.trim().isEmpty)) {
      throw ArgumentError('Settled cheques need a settlement journal id.');
    }
  }

  final String id;
  final String storeId;
  final PartyType partyType;
  final String partyId;
  final Money amount;
  final String chequeNumber;
  final String bankName;
  final DateTime receivedAt;
  final ChequeStatus status;
  final DateTime? dueDate;
  final String? description;
  final String? journalEntryId;
  final String? settlementJournalEntryId;

  StoreContext contextFor(String userId) {
    return StoreContext(storeId: storeId, userId: userId);
  }

  Cheque copyWith({ChequeStatus? status, String? settlementJournalEntryId}) {
    return Cheque(
      id: id,
      storeId: storeId,
      partyType: partyType,
      partyId: partyId,
      amount: amount,
      chequeNumber: chequeNumber,
      bankName: bankName,
      receivedAt: receivedAt,
      status: status ?? this.status,
      dueDate: dueDate,
      description: description,
      journalEntryId: journalEntryId,
      settlementJournalEntryId:
          settlementJournalEntryId ?? this.settlementJournalEntryId,
    );
  }

  static void _ensureIdentifier(String value, String label) {
    if (value.trim().isEmpty || value.contains('/')) {
      throw ArgumentError('$label is invalid.');
    }
  }
}
