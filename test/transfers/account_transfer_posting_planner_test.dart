import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/core/idempotency/idempotency_key.dart';
import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/transfers/domain/domain.dart';

void main() {
  const context = StoreContext(storeId: 'store-1', userId: 'user-1');

  test('prepares a balanced cash to bank transfer', () {
    final transfer = AccountTransfer(
      id: 'transfer-1',
      storeId: 'store-1',
      idempotencyKey: const IdempotencyKey('transfer-1'),
      postedAt: DateTime.utc(2026, 1, 5),
      fromAccountId: '1110',
      toAccountId: '1121',
      amount: const Money(minorUnits: 50000, currency: 'ILS'),
    );

    final result = const AccountTransferPostingPlanner().prepare(
      context: context,
      transfer: transfer,
    );

    expect(result, isA<Success<AccountTransferPostingPlan>>());
    final plan = (result as Success<AccountTransferPostingPlan>).value;
    expect(plan.journalEntry.isBalanced, isTrue);
    expect(plan.journalEntry.totalDebit.minorUnits, 50000);
    expect(plan.journalEntry.totalCredit.minorUnits, 50000);
    expect(plan.journalEntry.lines.first.accountId, '1121');
    expect(plan.journalEntry.lines.last.accountId, '1110');
  });

  test('rejects the same source and destination account', () {
    expect(
      () => AccountTransfer(
        id: 'transfer-1',
        storeId: 'store-1',
        idempotencyKey: const IdempotencyKey('transfer-1'),
        postedAt: DateTime.utc(2026, 1, 5),
        fromAccountId: '1110',
        toAccountId: '1110',
        amount: const Money(minorUnits: 50000, currency: 'ILS'),
      ),
      throwsArgumentError,
    );
  });
}
