import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/account.dart';
import '../../domain/enums/accounting_enums.dart';

abstract final class AccountFirestoreMapper {
  static Account fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? const <String, dynamic>{};

    return Account(
      id: _string(data['id'], snapshot.id),
      storeId: _string(data['storeId'], ''),
      code: _string(data['code'], snapshot.id),
      name: _string(data['name'], snapshot.id),
      type: _enumValue(data['type'], AccountType.values, AccountType.asset),
      normalSide: _enumValue(
        data['normalSide'],
        NormalSide.values,
        NormalSide.debit,
      ),
      controlType: _enumValue(
        data['controlType'],
        ControlType.values,
        ControlType.none,
      ),
      statementSection: _enumValue(
        data['statementSection'],
        StatementSection.values,
        StatementSection.currentAsset,
      ),
      parentId: data['parentId'] as String?,
      currency: _string(data['currency'], 'ILS'),
      isHeader: data['isHeader'] is bool ? data['isHeader'] as bool : false,
      sortOrder: _int(data['sortOrder'], 0),
      isActive: data['isActive'] is bool ? data['isActive'] as bool : true,
    );
  }

  static Map<String, dynamic> toMap(Account account) {
    return <String, dynamic>{
      'id': account.id,
      'storeId': account.storeId,
      'code': account.code,
      'name': account.name,
      'type': account.type.name,
      'normalSide': account.normalSide.name,
      'controlType': account.controlType.name,
      'statementSection': account.statementSection.name,
      'parentId': account.parentId,
      'currency': account.currency,
      'isHeader': account.isHeader,
      'sortOrder': account.sortOrder,
      'isActive': account.isActive,
    };
  }

  static T _enumValue<T extends Enum>(Object? raw, List<T> values, T fallback) {
    final name = raw is String ? raw : '';
    return values.firstWhere(
      (value) => value.name == name,
      orElse: () => fallback,
    );
  }

  static String _string(Object? value, String fallback) {
    return value is String && value.isNotEmpty ? value : fallback;
  }

  static int _int(Object? value, int fallback) {
    return value is int
        ? value
        : value is num
            ? value.toInt()
            : fallback;
  }
}
