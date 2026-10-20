import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/core/idempotency/idempotency_key.dart';
import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/core/quantity/quantity.dart';
import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/parties/domain/enums/party_type.dart';
import 'package:electrical_parts_store_v2/features/payments/domain/entities/party_payment.dart';
import 'package:electrical_parts_store_v2/features/payments/domain/entities/party_payment_posting_plan.dart';
import 'package:electrical_parts_store_v2/features/payments/domain/enums/party_payment_method.dart';
import 'package:electrical_parts_store_v2/features/payments/domain/services/party_payment_posting_planner.dart';
import 'package:electrical_parts_store_v2/features/purchases/domain/entities/purchase.dart';
import 'package:electrical_parts_store_v2/features/purchases/domain/entities/purchase_line.dart';
import 'package:electrical_parts_store_v2/features/purchases/domain/entities/purchase_posting_plan.dart';
import 'package:electrical_parts_store_v2/features/purchases/domain/enums/purchase_payment_method.dart';
import 'package:electrical_parts_store_v2/features/purchases/domain/services/purchase_posting_planner.dart';
import 'package:electrical_parts_store_v2/features/sales/domain/entities/sale.dart';
import 'package:electrical_parts_store_v2/features/sales/domain/entities/sale_line.dart';
import 'package:electrical_parts_store_v2/features/sales/domain/entities/sale_posting_plan.dart';
import 'package:electrical_parts_store_v2/features/sales/domain/enums/sale_payment_method.dart';
import 'package:electrical_parts_store_v2/features/sales/domain/services/sale_posting_planner.dart';

void main() {
  const context = StoreContext(storeId: 'store-1', userId: 'user-1');
  final postedAt = DateTime.utc(2026, 1, 1);

  SaleLine saleLine() {
    return SaleLine(
      id: 'sale-line-1',
      productId: 'product-1',
      description: 'Cable',
      quantity: const Quantity.fromMilliUnits(2000),
      unitFactorToBase: const Quantity.fromMilliUnits(1000),
      unitPrice: const Money(minorUnits: 1500),
      unitCost: const Money(minorUnits: 800),
      discount: const Money.zero(),
    );
  }

  PurchaseLine purchaseLine() {
    return PurchaseLine(
      id: 'purchase-line-1',
      productId: 'product-1',
      description: 'Cable',
      quantity: const Quantity.fromMilliUnits(2000),
      unitFactorToBase: const Quantity.fromMilliUnits(1000),
      unitCost: const Money(minorUnits: 1000),
      discount: const Money(minorUnits: 100),
    );
  }

  test('sale planner creates cash, revenue, tax, and cost postings', () {
    final sale = Sale(
      id: 'sale-1',
      storeId: context.storeId,
      idempotencyKey: const IdempotencyKey('sale-key-1'),
      postedAt: postedAt,
      paymentMethod: SalePaymentMethod.cash,
      lines: [saleLine()],
      tax: const Money(minorUnits: 100),
    );
    final result = const SalePostingPlanner().prepare(
      context: context,
      sale: sale,
      accounts: const SalePostingAccounts(
        settlementAccountId: '1110',
        customerReceivableAccountId: '1140',
        salesAccountId: '4100',
        inventoryAccountId: '1150',
        costOfSalesAccountId: '5100',
        taxAccountId: '2120',
      ),
    );

    expect(result, isA<Success<SalePostingPlan>>());
    final plan = (result as Success<SalePostingPlan>).value;
    expect(plan.journalEntry.isBalanced, isTrue);
    expect(plan.journalEntry.totalDebit, const Money(minorUnits: 4700));
    expect(plan.journalEntry.totalCredit, const Money(minorUnits: 4700));
    expect(
      plan.journalEntry.lines.map((line) => line.accountId),
      containsAll(<String>['1110', '4100', '2120', '5100', '1150']),
    );
    expect(plan.inventoryMovements.single.quantityDelta,
        const Quantity.fromMilliUnits(-2000));
    expect(plan.inventoryMovements.single.totalCost,
        const Money(minorUnits: 1600));
  });

  test('credit purchase planner posts inventory, input tax, and supplier payable',
      () {
    final purchase = Purchase(
      id: 'purchase-1',
      storeId: context.storeId,
      idempotencyKey: const IdempotencyKey('purchase-key-1'),
      postedAt: postedAt,
      paymentMethod: PurchasePaymentMethod.credit,
      supplierId: 'supplier-1',
      lines: [purchaseLine()],
      tax: const Money(minorUnits: 200),
    );
    final result = const PurchasePostingPlanner().prepare(
      context: context,
      purchase: purchase,
      accounts: const PurchasePostingAccounts(
        inventoryAccountId: '1150',
        supplierPayableAccountId: '2110',
        inputTaxAccountId: '1170',
      ),
    );

    expect(result, isA<Success<PurchasePostingPlan>>());
    final plan = (result as Success<PurchasePostingPlan>).value;
    expect(plan.journalEntry.isBalanced, isTrue);
    expect(plan.journalEntry.totalDebit, const Money(minorUnits: 2100));
    expect(plan.journalEntry.totalCredit, const Money(minorUnits: 2100));
    expect(
      plan.journalEntry.lines.map((line) => line.accountId),
      containsAll(<String>['1150', '1170', '2110']),
    );
    expect(plan.inventoryMovements.single.quantityDelta,
        const Quantity.fromMilliUnits(2000));
    expect(plan.inventoryMovements.single.totalCost,
        const Money(minorUnits: 1900));
  });

  test('customer receipt credits receivables and debits settlement', () {
    final payment = PartyPayment(
      id: 'payment-1',
      storeId: context.storeId,
      idempotencyKey: const IdempotencyKey('payment-key-1'),
      postedAt: postedAt,
      partyType: PartyType.customer,
      partyId: 'customer-1',
      paymentMethod: PartyPaymentMethod.cash,
      amount: const Money(minorUnits: 500),
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
    expect(plan.journalEntry.lines.first.debit,
        const Money(minorUnits: 500));
    expect(plan.journalEntry.lines.last.credit,
        const Money(minorUnits: 500));
    expect(plan.partyLedgerEntry.debit, const Money.zero());
    expect(plan.partyLedgerEntry.credit, const Money(minorUnits: 500));
  });

  test('supplier payment debits payables and credits settlement', () {
    final payment = PartyPayment(
      id: 'payment-2',
      storeId: context.storeId,
      idempotencyKey: const IdempotencyKey('payment-key-2'),
      postedAt: postedAt,
      partyType: PartyType.supplier,
      partyId: 'supplier-1',
      paymentMethod: PartyPaymentMethod.bank,
      amount: const Money(minorUnits: 500),
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
    expect(plan.journalEntry.lines.first.credit,
        const Money(minorUnits: 500));
    expect(plan.journalEntry.lines.last.debit,
        const Money(minorUnits: 500));
    expect(plan.partyLedgerEntry.debit, const Money(minorUnits: 500));
    expect(plan.partyLedgerEntry.credit, const Money.zero());
  });

  test('planner rejects a transaction from another store', () {
    final sale = Sale(
      id: 'sale-2',
      storeId: 'other-store',
      idempotencyKey: const IdempotencyKey('sale-key-2'),
      postedAt: postedAt,
      paymentMethod: SalePaymentMethod.cash,
      lines: [saleLine()],
      tax: const Money.zero(),
    );
    final result = const SalePostingPlanner().prepare(
      context: context,
      sale: sale,
      accounts: const SalePostingAccounts(
        settlementAccountId: '1110',
        customerReceivableAccountId: '1140',
        salesAccountId: '4100',
        inventoryAccountId: '1150',
        costOfSalesAccountId: '5100',
      ),
    );

    expect(result, isA<FailureResult<SalePostingPlan>>());
  });
}
