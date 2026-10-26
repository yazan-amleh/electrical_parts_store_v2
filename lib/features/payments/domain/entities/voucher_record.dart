import '../../../../core/money/money.dart';
import '../../../parties/domain/enums/party_type.dart';
import '../enums/party_payment_method.dart';

class VoucherRecord {
  const VoucherRecord({required this.id, required this.storeId, required this.partyType, required this.partyId, required this.paymentMethod, required this.amount, required this.postedAt, required this.journalEntryId, required this.status, this.description});
  final String id;
  final String storeId;
  final PartyType partyType;
  final String partyId;
  final PartyPaymentMethod paymentMethod;
  final Money amount;
  final DateTime postedAt;
  final String journalEntryId;
  final String status;
  final String? description;
  bool get isReceipt => partyType == PartyType.customer;
  String get statusLabel => switch (status) {
    'posted' => 'مرحّل',
    'pending' => 'شيك قيد التحصيل',
    'cleared' => 'شيك محصّل',
    'bounced' => 'شيك مرتجع',
    _ => 'حالة غير معروفة',
  };
}

class VoucherCursor {
  const VoucherCursor({required this.id, required this.postedAt});
  final String id;
  final DateTime postedAt;
}

class VoucherPage {
  VoucherPage({required List<VoucherRecord> records, required this.hasMore, required this.nextCursor}) : records = List.unmodifiable(records);
  final List<VoucherRecord> records;
  final bool hasMore;
  final VoucherCursor? nextCursor;
}
