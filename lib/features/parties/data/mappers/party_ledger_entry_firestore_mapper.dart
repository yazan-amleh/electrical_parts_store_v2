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
    final data = snapshot.data();
    if (data == null) {
      throw const FormatException('Party ledger document is empty.');
    }

    final partyTypeName = _requiredString(data['partyType'], 'partyType');
    final partyType = PartyType.values.where(
      (type) => type.name == partyTypeName,
    );
    if (partyType.length != 1) {
      throw FormatException('Unknown party ledger type: $partyTypeName.');
    }

    final description = data['description'];
    if (description != null && description is! String) {
      throw const FormatException(
        'Party ledger description must be text when present.',
      );
    }

    return PartyLedgerEntry(
      id: snapshot.id,
      storeId: _requiredString(data['storeId'], 'storeId'),
      partyType: partyType.single,
      partyId: _requiredString(data['partyId'], 'partyId'),
      sourceType: _requiredString(data['sourceType'], 'sourceType'),
      sourceId: _requiredString(data['sourceId'], 'sourceId'),
      postedAt: _requiredDate(data['postedAt'], 'postedAt'),
      debit: Money(
        minorUnits: _requiredInt(data['debitMinorUnits'], 'debitMinorUnits'),
        currency: _requiredString(data['currency'], 'currency'),
      ),
      credit: Money(
        minorUnits: _requiredInt(data['creditMinorUnits'], 'creditMinorUnits'),
        currency: _requiredString(data['currency'], 'currency'),
      ),
      description: description as String?,
    );
  }

  static DateTime _requiredDate(Object? value, String field) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    throw FormatException('Party ledger $field is invalid.');
  }

  static String _requiredString(Object? value, String field) {
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
    throw FormatException('Party ledger $field is invalid.');
  }

  static int _requiredInt(Object? value, String field) {
    if (value is int) {
      return value;
    }
    throw FormatException('Party ledger $field is invalid.');
  }
}
