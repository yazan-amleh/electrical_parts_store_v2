import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/core/idempotency/idempotency_key.dart';
import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/core/quantity/quantity.dart';
import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/purchases/domain/domain.dart';

void main() {
  const context = StoreContext(storeId: 'store-1', userId: 'user-1');

  test('prepares a balanced cash purchase and receipt', () {
    final purchase = Purchase(
      id: 'purchase-1',
      storeId: 'store-1',
      idempotencyKey: const IdempotencyKey('purchase-1'),
      postedAt: DateTime.utc(2026, 1, 1),
      paymentMethod: PurchasePaymentMethod.cash,
      tax: const Money(minorUnits: 180, currency: 'ILS'),
      lines: <PurchaseLine>[
        PurchaseLine(
          id: 'line-1',
          productId: 'product-1',
          description: 'Cable',
          quantity: Quantity.fromDouble(2),
          unitFactorToBase: Quantity.fromDouble(1),
          unitCost: const Money(minorUnits: 600, currency: 'ILS'),
          discount: const Money(minorUnits: 100, currency: 'ILS'),
        ),
      ],
    );

    const accounts = PurchasePostingAccounts(
      settlementAccountId: '1110',
      inventoryAccountId: '1150',
      inputTaxAccountId: '1170',
    );

    final result = const PurchasePostingPlanner().prepare(
      context: context,
      purchase: purchase,
      accounts: accounts,
    );

    expect(result, isA<Success<PurchasePostingPlan>>());
    final plan = (result as Success<PurchasePostingPlan>).value;

    expect(plan.journalEntry.isBalanced, isTrue);
    expect(plan.journalEntry.totalDebit.minorUnits, 1280);
    expect(plan.journalEntry.totalCredit.minorUnits, 1280);
    expect(plan.inventoryMovements, hasLength(1));
    expect(plan.inventoryMovements.single.quantityDelta.milliUnits, 2000);
    expect(plan.inventoryMovements.single.totalCost.minorUnits, 1100);
  });

  test('requires a supplier for credit purchases', () {
    expect(
      () => Purchase(
        id: 'purchase-1',
        storeId: 'store-1',
        idempotencyKey: const IdempotencyKey('purchase-1'),
        postedAt: DateTime.utc(2026, 1, 1),
        paymentMethod: PurchasePaymentMethod.credit,
        tax: const Money(minorUnits: 0, currency: 'ILS'),
        lines: <PurchaseLine>[
          PurchaseLine(
            id: 'line-1',
            productId: 'product-1',
            description: 'Cable',
            quantity: Quantity.fromDouble(1),
            unitFactorToBase: Quantity.fromDouble(1),
            unitCost: const Money(minorUnits: 600, currency: 'ILS'),
            discount: const Money(minorUnits: 0, currency: 'ILS'),
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('requires the input tax account when tax is present', () {
    final purchase = Purchase(
      id: 'purchase-1',
      storeId: 'store-1',
      idempotencyKey: const IdempotencyKey('purchase-1'),
      postedAt: DateTime.utc(2026, 1, 1),
      paymentMethod: PurchasePaymentMethod.cash,
      tax: const Money(minorUnits: 180, currency: 'ILS'),
      lines: <PurchaseLine>[
        PurchaseLine(
          id: 'line-1',
          productId: 'product-1',
          description: 'Cable',
          quantity: Quantity.fromDouble(1),
          unitFactorToBase: Quantity.fromDouble(1),
          unitCost: const Money(minorUnits: 600, currency: 'ILS'),
          discount: const Money(minorUnits: 0, currency: 'ILS'),
        ),
      ],
    );

    const noTaxAccount = PurchasePostingAccounts(
      settlementAccountId: '1110',
      inventoryAccountId: '1150',
    );

    final result = const PurchasePostingPlanner().prepare(
      context: context,
      purchase: purchase,
      accounts: noTaxAccount,
    );

    expect(result, isA<FailureResult<PurchasePostingPlan>>());
  });
}
