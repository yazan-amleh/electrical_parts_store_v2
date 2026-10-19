import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/features/accounting/domain/entities/journal_entry.dart';
import 'package:electrical_parts_store_v2/features/accounting/domain/entities/journal_line.dart';

void main() {
  test('accepts a balanced entry', () {
    final entry = JournalEntry(
      id: 'entry-1',
      storeId: 'store-1',
      idempotencyKey: 'sale-1',
      postedAt: DateTime.utc(2026, 1, 1),
      sourceType: 'sale',
      lines: [
        JournalLine(
          id: 'line-1',
          accountId: 'cash',
          debit: const Money(minorUnits: 1000),
          credit: const Money.zero(),
        ),
        JournalLine(
          id: 'line-2',
          accountId: 'sales',
          debit: const Money.zero(),
          credit: const Money(minorUnits: 1000),
        ),
      ],
    );

    expect(entry.isBalanced, isTrue);
  });

  test('rejects an unbalanced entry', () {
    expect(
      () => JournalEntry(
        id: 'entry-2',
        storeId: 'store-1',
        idempotencyKey: 'sale-2',
        postedAt: DateTime.utc(2026, 1, 1),
        sourceType: 'sale',
        lines: [
          JournalLine(
            id: 'line-1',
            accountId: 'cash',
            debit: const Money(minorUnits: 1000),
            credit: const Money.zero(),
          ),
          JournalLine(
            id: 'line-2',
            accountId: 'sales',
            debit: const Money.zero(),
            credit: const Money(minorUnits: 900),
          ),
        ],
      ),
      throwsArgumentError,
    );
  });
}
