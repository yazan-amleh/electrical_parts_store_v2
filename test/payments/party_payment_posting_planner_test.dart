import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/core/idempotency/idempotency_key.dart';
import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/payments/domain/domain.dart';
import 'package:electrical_parts_store_v2/features/parties/domain/enums/party_type.dart';

void main() {
  const context = StoreContext(storeId: 'store-1', userId: 'user-1');

  test('prepares a balanced customer receipt', () {
    final payment = PartyPayment(
      id: 'receipt-1',
      storeId: 'store-1',
      idempotencyKey: const IdempotencyKey('receipt-1'),
      postedAt: DateTime.utc(2026, 1, 2),
      partyType: PartyType.customer,
      partyId: 'customer-1',
      paymentMethod: PartyPaymentMethod.cash,
      amount: const Money(minorUnits: 12500, currency: 'ILS'),
    );

    final result = const PartyPaymentPostingPlanner().prepare(
      context: context,
      payment: payment,
      accounts: const PartyPaymentPostingAccounts(
        settlementAccountId: '1110',
        partyAccountId: '1140',
      ),
    );

    expect(result, isA<Success<PartyPaymentPostingPlan>>());
    final plan = (result as Success<PartyPaymentPostingPlan>).value;
    expect(plan.journalEntry.isBalanced, isTrue);
    expect(plan.journalEntry.totalDebit.minorUnits, 12500);
    expect(plan.journalEntry.totalCredit.minorUnits, 12500);
    expect(plan.journalEntry.lines.first.accountId, '1110');
    expect(plan.partyLedgerEntry.debit.isZero, isTrue);
    expect(plan.partyLedgerEntry.credit.minorUnits, 12500);
  });

  test('prepares a balanced supplier payment', () {
    final payment = PartyPayment(
      id: 'payment-1',
      storeId: 'store-1',
      idempotencyKey: const IdempotencyKey('payment-1'),
      postedAt: DateTime.utc(2026, 1, 3),
      partyType: PartyType.supplier,
      partyId: 'supplier-1',
      paymentMethod: PartyPaymentMethod.bank,
      amount: const Money(minorUnits: 8300, currency: 'ILS'),
    );

    final result = const PartyPaymentPostingPlanner().prepare(
      context: context,
      payment: payment,
      accounts: const PartyPaymentPostingAccounts(
        settlementAccountId: '1121',
        partyAccountId: '2110',
      ),
    );

    expect(result, isA<Success<PartyPaymentPostingPlan>>());
    final plan = (result as Success<PartyPaymentPostingPlan>).value;
    expect(plan.journalEntry.isBalanced, isTrue);
    expect(plan.journalEntry.lines.first.accountId, '1121');
    expect(plan.journalEntry.lines.first.credit.minorUnits, 8300);
    expect(plan.partyLedgerEntry.debit.minorUnits, 8300);
    expect(plan.partyLedgerEntry.credit.isZero, isTrue);
  });

  test('requires a positive amount', () {
    expect(
      () => PartyPayment(
        id: 'payment-1',
        storeId: 'store-1',
        idempotencyKey: const IdempotencyKey('payment-1'),
        postedAt: DateTime.utc(2026, 1, 3),
        partyType: PartyType.supplier,
        partyId: 'supplier-1',
        paymentMethod: PartyPaymentMethod.cash,
        amount: const Money(minorUnits: 0, currency: 'ILS'),
      ),
      throwsArgumentError,
    );
  });
}
