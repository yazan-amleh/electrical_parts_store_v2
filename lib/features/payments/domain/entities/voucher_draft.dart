import '../../../../core/money/money.dart';
import '../../../parties/domain/enums/party_type.dart';

class VoucherDraft {
  const VoucherDraft({
    required this.id,
    required this.storeId,
    required this.createdBy,
    required this.status,
    required this.partyId,
    required this.partyType,
    required this.amount,
    required this.description,
    required this.postedAt,
    this.approvedBy,
    this.journalEntryId,
    this.rejectionReason,
  });

  final String id;
  final String storeId;
  final String createdBy;
  final String status;
  final String partyId;
  final PartyType partyType;
  final Money amount;
  final String? description;
  final DateTime postedAt;
  final String? approvedBy;
  final String? journalEntryId;
  final String? rejectionReason;

  String get statusLabel => switch (status) {
        'draft' => 'مسودة',
        'pendingApproval' => 'بانتظار الاعتماد',
        'posted' => 'مرحّل',
        'rejected' => 'مرفوض',
        _ => 'حالة غير معروفة',
      };
}
