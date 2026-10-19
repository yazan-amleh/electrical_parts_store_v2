import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/accounting/data/repositories/in_memory_accounting_repository.dart';
import 'package:electrical_parts_store_v2/features/accounting/domain/entities/account.dart';
import 'package:electrical_parts_store_v2/features/accounting/domain/entities/journal_entry.dart';
import 'package:electrical_parts_store_v2/features/accounting/domain/entities/journal_line.dart';
import 'package:electrical_parts_store_v2/features/accounting/domain/entities/posting_result.dart';
import 'package:electrical_parts_store_v2/features/accounting/domain/enums/accounting_enums.dart';
import 'package:electrical_parts_store_v2/features/accounting/domain/services/journal_posting_engine.dart';

void main() {
  final cash = Account(
    id: 'cash',
    storeId: 'store-1',
    code: '1110',
    name: 'الصندوق',
    type: AccountType.asset,
    normalSide: NormalSide.debit,
    controlType: ControlType.cashBox,
    statementSection: StatementSection.currentAsset,
  );

  final sales = Account(
    id: 'sales',
    storeId: 'store-1',
    code: '4100',
    name: 'المبيعات',
    type: AccountType.revenue,
    normalSide: NormalSide.credit,
    controlType: ControlType.none,
    statementSection: StatementSection.revenue,
  );

  JournalEntry saleEntry(String id) {
    return JournalEntry(
      id: id,
      storeId: 'store-1',
      idempotencyKey: 'sale-$id',
      postedAt: DateTime.utc(2026, 1, 1),
      sourceType: 'sale',
      lines: [
        JournalLine(
          id: '$id-cash',
          accountId: cash.id,
          debit: const Money(minorUnits: 1000),
          credit: const Money.zero(),
        ),
        JournalLine(
          id: '$id-sales',
          accountId: sales.id,
          debit: const Money.zero(),
          credit: const Money(minorUnits: 1000),
        ),
      ],
    );
  }

  test('prepares a balanced entry only for valid store accounts', () {
    final result = const JournalPostingEngine().prepare(
      context: const StoreContext(storeId: 'store-1', userId: 'user-1'),
      entry: saleEntry('entry-1'),
      accounts: <String, Account>{'cash': cash, 'sales': sales},
    );

    expect(result, isA<Success<PostingResult>>());
    final posting = (result as Success<PostingResult>).value;
    expect(posting.deltas, hasLength(2));
  });

  test('does not post the same idempotency key twice', () async {
    final repository = InMemoryAccountingRepository(
      accounts: [cash, sales],
    );
    const context = StoreContext(storeId: 'store-1', userId: 'user-1');
    final entry = saleEntry('entry-2');

    expect(
      (await repository.postJournalEntry(
        context: context,
        entry: entry,
      )),
      isA<Success<JournalEntry>>(),
    );
    expect(
      (await repository.postJournalEntry(
        context: context,
        entry: entry,
      )),
      isA<Success<JournalEntry>>(),
    );

    final balance = await repository.getAccountBalance(
      context: context,
      accountId: 'cash',
    );
    expect((balance as Success<Money>).value, const Money(minorUnits: 1000));
  });

  test('rejects an account from another store', () {
    final otherStoreCash = Account(
      id: 'other-cash',
      storeId: 'store-2',
      code: '1110',
      name: 'صندوق آخر',
      type: AccountType.asset,
      normalSide: NormalSide.debit,
      controlType: ControlType.cashBox,
      statementSection: StatementSection.currentAsset,
    );

    final result = const JournalPostingEngine().prepare(
      context: const StoreContext(storeId: 'store-1', userId: 'user-1'),
      entry: JournalEntry(
        id: 'entry-3',
        storeId: 'store-1',
        idempotencyKey: 'sale-entry-3',
        postedAt: DateTime.utc(2026, 1, 1),
        sourceType: 'sale',
        lines: [
          JournalLine(
            id: 'line-1',
            accountId: 'other-cash',
            debit: Money(minorUnits: 1000),
            credit: Money.zero(),
          ),
          JournalLine(
            id: 'line-2',
            accountId: 'sales',
            debit: Money.zero(),
            credit: Money(minorUnits: 1000),
          ),
        ],
      ),
      accounts: <String, Account>{
        'other-cash': otherStoreCash,
        'sales': sales,
      },
    );

    expect(result, isA<FailureResult<PostingResult>>());
  });
}
