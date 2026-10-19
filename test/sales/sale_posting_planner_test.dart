import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/core/idempotency/idempotency_key.dart';
import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/core/quantity/quantity.dart';
import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/sales/domain/domain.dart';

void main() {
  const context = StoreContext(storeId: 'store-1', userId: 'user-1');
  const accounts = SalePostingAccounts(
    settlementAccountId: '1110',
    salesAccountId: '4100',
    inventoryAccountId: '1150',
    costOfSalesAccountId: '5100',
    taxAccountId: '2120',
  );

  test('prepares a balanced cash sale and inventory issue', () {
    final sale = Sale(
      id: 'sale-1',
      storeId: 'store-1',
      idempotencyKey: const IdempotencyKey('sale-1'),
      postedAt: DateTime.utc(2026, 1, 1),
      paymentMethod: SalePaymentMethod.cash,
      tax: const Money(minorUnits: 180, currency: 'ILS'),
      lines: <SaleLine>[
        SaleLine(
          id: 'line-1',
          productId: 'product-1',
          description: 'Cable',
          quantity: Quantity.fromDouble(2),
          unitFactorToBase: Quantity.fromDouble(1),
          unitPrice: const Money(minorUnits: 1000, currency: 'ILS'),
          unitCost: const Money(minorUnits: 600, currency: 'ILS'),
          discount: const Money(minorUnits: 0, currency: 'ILS'),
        ),
      ],
    );

    final result = const SalePostingPlanner().prepare(
      context: context,
      sale: sale,
      accounts: accounts,
    );

    expect(result, isA<Success<SalePostingPlan>>());
    final plan = (result as Success<SalePostingPlan>).value;

    expect(plan.journalEntry.isBalanced, isTrue);
    expect(plan.journalEntry.totalDebit.minorUnits, 3380);
    expect(plan.journalEntry.totalCredit.minorUnits, 3380);
    expect(plan.inventoryMovements, hasLength(1));
    expect(plan.inventoryMovements.single.quantityDelta.milliUnits, -2000);
    expect(plan.inventoryMovements.single.unitCost.minorUnits, 600);
  });

  test('converts selected units to base inventory quantity', () {
    final line = SaleLine(
      id: 'line-1',
      productId: 'product-1',
      description: 'Box of terminals',
      quantity: Quantity.fromDouble(2),
      unitFactorToBase: Quantity.fromDouble(10),
      unitPrice: const Money(minorUnits: 5000, currency: 'ILS'),
      unitCost: const Money(minorUnits: 300, currency: 'ILS'),
      discount: const Money(minorUnits: 0, currency: 'ILS'),
    );

    expect(line.baseQuantity.value, 20);
    expect(line.total.minorUnits, 10000);
    expect(line.costTotal.minorUnits, 6000);
  });

  test('requires a customer for credit sales', () {
    expect(
      () => Sale(
        id: 'sale-1',
        storeId: 'store-1',
        idempotencyKey: const IdempotencyKey('sale-1'),
        postedAt: DateTime.utc(2026, 1, 1),
        paymentMethod: SalePaymentMethod.credit,
        tax: const Money(minorUnits: 0, currency: 'ILS'),
        lines: <SaleLine>[
          SaleLine(
            id: 'line-1',
            productId: 'product-1',
            description: 'Cable',
            quantity: Quantity.fromDouble(1),
            unitFactorToBase: Quantity.fromDouble(1),
            unitPrice: const Money(minorUnits: 1000, currency: 'ILS'),
            unitCost: const Money(minorUnits: 600, currency: 'ILS'),
            discount: const Money(minorUnits: 0, currency: 'ILS'),
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('routes credit sales to customer receivables', () {
    final sale = Sale(
      id: 'sale-credit-1',
      storeId: 'store-1',
      idempotencyKey: const IdempotencyKey('sale-credit-1'),
      postedAt: DateTime.utc(2026, 1, 1),
      paymentMethod: SalePaymentMethod.credit,
      customerId: 'customer-1',
      tax: const Money(minorUnits: 0, currency: 'ILS'),
      lines: <SaleLine>[
        SaleLine(
          id: 'line-1',
          productId: 'product-1',
          description: 'Cable',
          quantity: Quantity.fromDouble(1),
          unitFactorToBase: Quantity.fromDouble(1),
          unitPrice: const Money(minorUnits: 1000, currency: 'ILS'),
          unitCost: const Money(minorUnits: 600, currency: 'ILS'),
          discount: const Money(minorUnits: 0, currency: 'ILS'),
        ),
      ],
    );

    const creditAccounts = SalePostingAccounts(
      settlementAccountId: '1110',
      customerReceivableAccountId: '1140',
      salesAccountId: '4100',
      inventoryAccountId: '1150',
      costOfSalesAccountId: '5100',
    );

    final result = const SalePostingPlanner().prepare(
      context: context,
      sale: sale,
      accounts: creditAccounts,
    );

    expect(result, isA<Success<SalePostingPlan>>());
    final plan = (result as Success<SalePostingPlan>).value;
    expect(plan.journalEntry.lines.first.accountId, '1140');
  });

  test('rejects tax without a tax account', () {
    final sale = Sale(
      id: 'sale-1',
      storeId: 'store-1',
      idempotencyKey: const IdempotencyKey('sale-1'),
      postedAt: DateTime.utc(2026, 1, 1),
      paymentMethod: SalePaymentMethod.cash,
      tax: const Money(minorUnits: 180, currency: 'ILS'),
      lines: <SaleLine>[
        SaleLine(
          id: 'line-1',
          productId: 'product-1',
          description: 'Cable',
          quantity: Quantity.fromDouble(1),
          unitFactorToBase: Quantity.fromDouble(1),
          unitPrice: const Money(minorUnits: 1000, currency: 'ILS'),
          unitCost: const Money(minorUnits: 600, currency: 'ILS'),
          discount: const Money(minorUnits: 0, currency: 'ILS'),
        ),
      ],
    );

    const noTaxAccount = SalePostingAccounts(
      settlementAccountId: '1110',
      salesAccountId: '4100',
      inventoryAccountId: '1150',
      costOfSalesAccountId: '5100',
    );

    final result = const SalePostingPlanner().prepare(
      context: context,
      sale: sale,
      accounts: noTaxAccount,
    );

    expect(result, isA<FailureResult<SalePostingPlan>>());
  });
}
