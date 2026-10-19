import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/journal_entry.dart';
import '../../domain/entities/journal_line.dart';

abstract final class JournalEntryFirestoreMapper {
  static Map<String, dynamic> header(JournalEntry entry) {
    return <String, dynamic>{
      'storeId': entry.storeId,
      'idempotencyKey': entry.idempotencyKey,
      'sourceType': entry.sourceType,
      'description': entry.description,
      'status': 'posted',
      'currency': entry.totalDebit.currency,
      'totalDebitMinorUnits': entry.totalDebit.minorUnits,
      'totalCreditMinorUnits': entry.totalCredit.minorUnits,
      'postedAt': Timestamp.fromDate(entry.postedAt.toUtc()),
    };
  }

  static Map<String, dynamic> line({
    required String storeId,
    required JournalLine line,
    required int lineNumber,
  }) {
    return <String, dynamic>{
      'storeId': storeId,
      'accountId': line.accountId,
      'description': line.description,
      'lineNumber': lineNumber,
      'currency': line.debit.currency,
      'debitMinorUnits': line.debit.minorUnits,
      'creditMinorUnits': line.credit.minorUnits,
    };
  }
}
