import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/money/money.dart';
import '../../domain/entities/operational_report.dart';

abstract final class ReportFirestoreMapper {
  static ReportTransaction? tryTransaction(
    DocumentSnapshot<Map<String, dynamic>> snapshot, {
    required String source,
  }) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final postedAt = _date(data['postedAt']);
    if (postedAt == null) {
      return null;
    }

    final currency = _string(data['currency'], 'ILS');
    final amountMinorUnits = _int(
      data['totalMinorUnits'],
      _int(data['amountMinorUnits']),
    );
    final costMinorUnits = _int(data['costTotalMinorUnits']);
    return ReportTransaction(
      id: snapshot.id,
      postedAt: postedAt,
      source: source,
      amount: Money(minorUnits: amountMinorUnits, currency: currency),
      cost: Money(minorUnits: costMinorUnits, currency: currency),
      description: _stringOrNull(data['description']),
      paymentMethod: _stringOrNull(data['paymentMethod']),
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

  static String _string(Object? value, String fallback) {
    return value is String && value.isNotEmpty ? value : fallback;
  }

  static String? _stringOrNull(Object? value) {
    return value is String && value.trim().isNotEmpty ? value : null;
  }

  static int _int(Object? value, [int fallback = 0]) {
    return value is int
        ? value
        : value is num
            ? value.toInt()
            : fallback;
  }
}
