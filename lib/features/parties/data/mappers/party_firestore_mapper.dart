import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/money/money.dart';
import '../../domain/entities/party.dart';
import '../../domain/entities/party_balance.dart';
import '../../domain/enums/party_type.dart';

abstract final class PartyFirestoreMapper {
  static Party fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final currency = _string(data['currency'], 'ILS');
    return Party(
      id: snapshot.id,
      storeId: _string(data['storeId'], ''),
      type: _partyType(data['partyType']),
      name: _string(data['name'], snapshot.id),
      phone: data['phone'] as String?,
      email: data['email'] as String?,
      address: data['address'] as String?,
      taxNumber: data['taxNumber'] as String?,
      notes: data['notes'] as String?,
      creditLimit: Money(
        minorUnits: _int(data['creditLimitMinorUnits']),
        currency: currency,
      ),
      isActive: data['isActive'] is bool ? data['isActive'] as bool : true,
    );
  }

  static PartyBalance balanceFromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final currency = _string(data['currency'], 'ILS');
    final partyType = _partyType(data['partyType']);
    final debit = Money(
      minorUnits: _int(data['debitMinorUnits']),
      currency: currency,
    );
    final credit = Money(
      minorUnits: _int(data['creditMinorUnits']),
      currency: currency,
    );
    return PartyBalance(
      partyType: partyType,
      partyId: _string(data['partyId'], ''),
      debit: debit,
      credit: credit,
      balance: Money(
        minorUnits: _int(
          data['balanceMinorUnits'],
          debit.minorUnits - credit.minorUnits,
        ),
        currency: currency,
      ),
    );
  }

  static Map<String, dynamic> toMap(Party party) {
    return <String, dynamic>{
      'storeId': party.storeId,
      'partyType': party.type.name,
      'name': party.name,
      'phone': party.phone,
      'email': party.email,
      'address': party.address,
      'taxNumber': party.taxNumber,
      'notes': party.notes,
      'currency': party.creditLimit.currency,
      'creditLimitMinorUnits': party.creditLimit.minorUnits,
      'isActive': party.isActive,
    };
  }

  static PartyType _partyType(Object? value) {
    return PartyType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => PartyType.customer,
    );
  }

  static String _string(Object? value, String fallback) {
    return value is String && value.isNotEmpty ? value : fallback;
  }

  static int _int(Object? value, [int fallback = 0]) {
    return value is int
        ? value
        : value is num
        ? value.toInt()
        : fallback;
  }
}
