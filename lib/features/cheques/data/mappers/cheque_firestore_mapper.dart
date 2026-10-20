import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/money/money.dart';
import '../../../parties/domain/enums/party_type.dart';
import '../../domain/entities/cheque.dart';
import '../../domain/enums/cheque_status.dart';

abstract final class ChequeFirestoreMapper {
  static Cheque fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final statusName = _string(data['status'], ChequeStatus.pending.name);
    final status = ChequeStatus.values.firstWhere(
      (candidate) => candidate.name == statusName,
      orElse: () => ChequeStatus.pending,
    );
    return Cheque(
      id: snapshot.id,
      storeId: _string(data['storeId']),
      partyType: PartyType.values.firstWhere(
        (candidate) =>
            candidate.name == _string(
              data['partyType'],
              PartyType.customer.name,
            ),
        orElse: () => PartyType.customer,
      ),
      partyId: _string(data['partyId']),
      amount: Money(
        minorUnits: _int(data['amountMinorUnits']),
        currency: _string(data['currency']),
      ),
      chequeNumber: _string(data['chequeNumber']),
      bankName: _string(data['bankName']),
      receivedAt: _date(data['postedAt']) ?? DateTime.now().toUtc(),
      status: status,
      dueDate: _date(data['dueDate']),
      description: data['description'] as String?,
      journalEntryId: data['journalEntryId'] as String?,
      settlementJournalEntryId: data['settlementJournalEntryId'] as String?,
    );
  }

  static DateTime? _date(Object? value) {
    if (value is Timestamp) {
      return value.toDate().toUtc();
    }
    if (value is DateTime) {
      return value.toUtc();
    }
    return null;
  }

  static int _int(Object? value) {
    return value is int
        ? value
        : value is num
            ? value.toInt()
            : 0;
  }

  static String _string(Object? value, [String fallback = '']) {
    return value is String && value.trim().isNotEmpty ? value : fallback;
  }
}
