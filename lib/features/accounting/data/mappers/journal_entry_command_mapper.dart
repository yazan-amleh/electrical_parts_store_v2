import '../../domain/entities/journal_entry.dart';

abstract final class JournalEntryCommandMapper {
  static Map<String, dynamic> toRequest(JournalEntry entry) {
    return <String, dynamic>{
      'storeId': entry.storeId,
      'entry': <String, dynamic>{
        'id': entry.id,
        'idempotencyKey': entry.idempotencyKey,
        'postedAt': entry.postedAt.toUtc().toIso8601String(),
        'sourceType': entry.sourceType,
        'description': entry.description,
        'currency': entry.totalDebit.currency,
        'lines': [
          for (var index = 0; index < entry.lines.length; index++)
            <String, dynamic>{
              'id': entry.lines[index].id,
              'accountId': entry.lines[index].accountId,
              'description': entry.lines[index].description,
              'debitMinorUnits': entry.lines[index].debit.minorUnits,
              'creditMinorUnits': entry.lines[index].credit.minorUnits,
              'lineNumber': index + 1,
            },
        ],
      },
    };
  }
}
