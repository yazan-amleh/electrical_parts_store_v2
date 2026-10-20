import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/core/idempotency/idempotency_key.dart';
import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/expenses/domain/domain.dart';
import 'package:electrical_parts_store_v2/features/parties/domain/enums/party_type.dart';

void main() {
  const context = StoreContext(storeId: 'store-1', userId: 'user-1');

  test('prepares a balanced cash expense with input tax', () {
    final expense = Expense(
      id: 'expense-1',
      storeId: 'store-1',
      idempotencyKey: const IdempotencyKey('expense-1'),
      postedAt: DateTime.utc(2026, 1, 4),
      paymentMethod: ExpensePaymentMethod.cash,
      expenseAccountId: '6110',
      amount: const Money(minorUnits: 10000, currency: 'ILS'),
      tax: const Money(minorUnits: 1600, currency: 'ILS'),
    );

    final result = const ExpensePostingPlanner().prepare(
      context: context,
      expense: expense,
      accounts: const ExpensePostingAccounts(
        settlementAccountId: '1110',
        inputTaxAccountId: '1170',
      ),
    );

    expect(result, isA<Success<ExpensePostingPlan>>());
    final plan = (result as Success<ExpensePostingPlan>).value;
    expect(plan.journalEntry.isBalanced, isTrue);
    expect(plan.journalEntry.totalDebit.minorUnits, 11600);
    expect(plan.journalEntry.totalCredit.minorUnits, 11600);
    expect(plan.partyLedgerEntry, isNull);
  });

  test('creates supplier ledger credit for a credit expense', () {
    final expense = Expense(
      id: 'expense-credit-1',
      storeId: 'store-1',
      idempotencyKey: const IdempotencyKey('expense-credit-1'),
      postedAt: DateTime.utc(2026, 1, 4),
      paymentMethod: ExpensePaymentMethod.credit,
      expenseAccountId: '6110',
      supplierId: 'supplier-1',
      amount: const Money(minorUnits: 8000, currency: 'ILS'),
      tax: const Money(minorUnits: 0, currency: 'ILS'),
    );

    final result = const ExpensePostingPlanner().prepare(
      context: context,
      expense: expense,
      accounts: const ExpensePostingAccounts(supplierPayableAccountId: '2110'),
    );

    expect(result, isA<Success<ExpensePostingPlan>>());
    final plan = (result as Success<ExpensePostingPlan>).value;
    expect(plan.partyLedgerEntry?.partyType, PartyType.supplier);
    expect(plan.partyLedgerEntry?.credit.minorUnits, 8000);
    expect(plan.journalEntry.lines.last.accountId, '2110');
  });

  test('requires an input tax account when tax is present', () {
    final expense = Expense(
      id: 'expense-1',
      storeId: 'store-1',
      idempotencyKey: const IdempotencyKey('expense-1'),
      postedAt: DateTime.utc(2026, 1, 4),
      paymentMethod: ExpensePaymentMethod.cash,
      expenseAccountId: '6110',
      amount: const Money(minorUnits: 10000, currency: 'ILS'),
      tax: const Money(minorUnits: 1600, currency: 'ILS'),
    );

    final result = const ExpensePostingPlanner().prepare(
      context: context,
      expense: expense,
      accounts: const ExpensePostingAccounts(settlementAccountId: '1110'),
    );

    expect(result, isA<FailureResult<ExpensePostingPlan>>());
  });
}
