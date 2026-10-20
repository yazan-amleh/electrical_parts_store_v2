import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/money/money.dart';
import '../../domain/entities/party_ledger_entry.dart';
import '../../domain/enums/party_type.dart';

abstract final class PartyLedgerEntryFirestoreMapper {
  static Map<String, dynamic> toMap(PartyLedgerEntry entry) {
    return <String, dynamic>{
      'storeId': entry.storeId,
      'partyType': entry.partyType.name,
      'partyId': entry.partyId,
      'sourceType': entry.sourceType,
      'sourceId': entry.sourceId,
      'postedAt': Timestamp.fromDate(entry.postedAt),
      'currency': entry.debit.currency,
      'debitMinorUnits': entry.debit.minorUnits,
      'creditMinorUnits': entry.credit.minorUnits,
      'description': entry.description,
    };
  }

  static PartyLedgerEntry fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final currency = _string(data['currency'], 'ILS');
    final partyTypeName = _string(data['partyType'], PartyType.customer.name);
    final partyType = PartyType.values.firstWhere(
      (type) => type.name == partyTypeName,
      orElse: () => PartyType.customer,
    );

    return PartyLedgerEntry(
      id: snapshot.id,
      storeId: _string(data['storeId'], ''),
      partyType: partyType,
      partyId: _string(data['partyId'], ''),
      sourceType: _string(data['sourceType'], ''),
      sourceId: _string(data['sourceId'], snapshot.id),
      postedAt: _date(data['postedAt']) ?? DateTime.now().toUtc(),
      debit: Money(
        minorUnits: _int(data['debitMinorUnits']),
        currency: currency,
      ),
      credit: Money(
        minorUnits: _int(data['creditMinorUnits']),
        currency: currency,
      ),
      description: data['description'] as String?,
    );
  }

  static DateTime? _date(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }

  static String _string(Object? value, String fallback) {
    return value is String && value.isNotEmpty ? value : fallback;
  }

  static int _int(Object? value) {
    return value is int
        ? value
        : value is num
        ? value.toInt()
        : 0;
  }
}
