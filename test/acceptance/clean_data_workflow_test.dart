import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/core/idempotency/idempotency_key.dart';
import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/core/quantity/quantity.dart';
import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/accounting/data/repositories/in_memory_accounting_repository.dart';
import 'package:electrical_parts_store_v2/features/accounting/domain/entities/journal_entry.dart';
import 'package:electrical_parts_store_v2/features/accounting/domain/services/default_chart_of_accounts.dart';
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
import 'package:electrical_parts_store_v2/features/repairs/data/mappers/repair_command_mapper.dart';
import 'package:electrical_parts_store_v2/features/repairs/domain/entities/repair_part.dart';
import 'package:electrical_parts_store_v2/features/repairs/domain/entities/repair_payment.dart';
import 'package:electrical_parts_store_v2/features/repairs/domain/entities/repair_posting_accounts.dart';
import 'package:electrical_parts_store_v2/features/repairs/domain/entities/repair_request.dart';
import 'package:electrical_parts_store_v2/features/repairs/domain/enums/repair_payment_kind.dart';
import 'package:electrical_parts_store_v2/features/sales/domain/entities/sale.dart';
import 'package:electrical_parts_store_v2/features/sales/domain/entities/sale_line.dart';
import 'package:electrical_parts_store_v2/features/sales/domain/entities/sale_posting_plan.dart';
import 'package:electrical_parts_store_v2/features/sales/domain/enums/sale_payment_method.dart';
import 'package:electrical_parts_store_v2/features/sales/domain/services/sale_posting_planner.dart';

void main() {
  const context = StoreContext(storeId: 'store-a', userId: 'owner-a');
  final postedAt = DateTime.utc(2026, 1, 1);

  Sale sale({String storeId = 'store-a', String id = 'sale-1'}) {
    return Sale(
      id: id,
      storeId: storeId,
      idempotencyKey: IdempotencyKey(id),
      postedAt: postedAt,
      paymentMethod: SalePaymentMethod.cash,
      lines: [
        SaleLine(
          id: '$id-line',
          productId: 'product-1',
          description: 'Cable',
          quantity: const Quantity.fromMilliUnits(2000),
          unitFactorToBase: const Quantity.fromMilliUnits(1000),
          unitPrice: const Money(minorUnits: 1500, currency: 'ILS'),
          unitCost: const Money(minorUnits: 800, currency: 'ILS'),
          discount: const Money.zero(currency: 'ILS'),
        ),
      ],
      tax: const Money(minorUnits: 100, currency: 'ILS'),
    );
  }

  Purchase purchase() {
    return Purchase(
      id: 'purchase-1',
      storeId: context.storeId,
      idempotencyKey: const IdempotencyKey('purchase-1'),
      postedAt: postedAt,
      paymentMethod: PurchasePaymentMethod.credit,
      supplierId: 'supplier-1',
      lines: [
        PurchaseLine(
          id: 'purchase-1-line',
          productId: 'product-1',
          description: 'Cable',
          quantity: const Quantity.fromMilliUnits(2000),
          unitFactorToBase: const Quantity.fromMilliUnits(1000),
          unitCost: const Money(minorUnits: 1000, currency: 'ILS'),
          discount: const Money(minorUnits: 100, currency: 'ILS'),
        ),
      ],
      tax: const Money(minorUnits: 200, currency: 'ILS'),
    );
  }

  PartyPayment customerReceipt() {
    return PartyPayment(
      id: 'customer-receipt-1',
      storeId: context.storeId,
      idempotencyKey: const IdempotencyKey('customer-receipt-1'),
      postedAt: postedAt,
      partyType: PartyType.customer,
      partyId: 'customer-1',
      paymentMethod: PartyPaymentMethod.cash,
      amount: const Money(minorUnits: 500, currency: 'ILS'),
    );
  }

  PartyPayment supplierPayment() {
    return PartyPayment(
      id: 'supplier-payment-1',
      storeId: context.storeId,
      idempotencyKey: const IdempotencyKey('supplier-payment-1'),
      postedAt: postedAt,
      partyType: PartyType.supplier,
      partyId: 'supplier-1',
      paymentMethod: PartyPaymentMethod.bank,
      amount: const Money(minorUnits: 500, currency: 'ILS'),
    );
  }

  RepairRequest repair() {
    return RepairRequest(
      id: 'repair-1',
      storeId: context.storeId,
      idempotencyKey: const IdempotencyKey('repair-1'),
      customerId: 'customer-1',
      deviceName: 'Inverter',
      deviceModel: 'INV-100',
      problemDescription: 'Does not start',
      createdAt: postedAt,
      receivedAt: postedAt,
      expectedDeliveryDate: DateTime.utc(2026, 1, 8),
      laborCost: const Money(minorUnits: 3000, currency: 'ILS'),
      parts: [
        RepairPart(
          id: 'repair-part-1',
          productId: 'product-1',
          productName: 'Fuse',
          quantity: const Quantity.fromMilliUnits(1500),
          unitPrice: const Money(minorUnits: 1250, currency: 'ILS'),
          unitCost: const Money(minorUnits: 700, currency: 'ILS'),
        ),
      ],
    );
  }

  Future<void> post(
    InMemoryAccountingRepository repository,
    JournalEntry entry,
  ) async {
    final result = await repository.postJournalEntry(
      context: context,
      entry: entry,
    );
    expect(result, isA<Success<JournalEntry>>());
  }

  Future<Money> balance(
    InMemoryAccountingRepository repository,
    String accountId,
  ) async {
    final result = await repository.getAccountBalance(
      context: context,
      accountId: accountId,
    );
    return (result as Success<Money>).value;
  }

  test(
    'runs a clean store workflow across sales, purchases, payments and repairs',
    () async {
    final repository = InMemoryAccountingRepository(
      accounts: DefaultChartOfAccounts.forStore(context.storeId),
    );

    final saleResult = const SalePostingPlanner().prepare(
      context: context,
      sale: sale(),
      accounts: const SalePostingAccounts(
        settlementAccountId: '1110',
        salesAccountId: '4100',
        inventoryAccountId: '1150',
        costOfSalesAccountId: '5100',
        taxAccountId: '2120',
      ),
    );
    expect(saleResult, isA<Success<SalePostingPlan>>());
    final salePlan = (saleResult as Success<SalePostingPlan>).value;

    final purchaseResult = const PurchasePostingPlanner().prepare(
      context: context,
      purchase: purchase(),
      accounts: const PurchasePostingAccounts(
        inventoryAccountId: '1150',
        supplierPayableAccountId: '2110',
        inputTaxAccountId: '1170',
      ),
    );
    expect(purchaseResult, isA<Success<PurchasePostingPlan>>());
    final purchasePlan = (purchaseResult as Success<PurchasePostingPlan>).value;

    final receiptResult = const PartyPaymentPostingPlanner().prepare(
      context: context,
      payment: customerReceipt(),
      accounts: const PartyPaymentPostingAccounts(
        settlementAccountId: '1110',
        partyAccountId: '1140',
      ),
    );
    expect(receiptResult, isA<Success<PartyPaymentPostingPlan>>());
    final receiptPlan =
        (receiptResult as Success<PartyPaymentPostingPlan>).value;

    final supplierPaymentResult = const PartyPaymentPostingPlanner().prepare(
      context: context,
      payment: supplierPayment(),
      accounts: const PartyPaymentPostingAccounts(
        settlementAccountId: '1121',
        partyAccountId: '2110',
      ),
    );
    expect(
      supplierPaymentResult,
      isA<Success<PartyPaymentPostingPlan>>(),
    );
    final supplierPaymentPlan =
        (supplierPaymentResult as Success<PartyPaymentPostingPlan>).value;

    await post(repository, purchasePlan.journalEntry);
    await post(repository, supplierPaymentPlan.journalEntry);
    await post(repository, salePlan.journalEntry);
    await post(repository, receiptPlan.journalEntry);

    expect(
      salePlan.totalIssuedQuantity,
      const Quantity.fromMilliUnits(-2000),
    );
    expect(
      purchasePlan.totalReceivedQuantity,
      const Quantity.fromMilliUnits(2000),
    );
    expect(await balance(repository, '1110'), const Money(minorUnits: 3600));
    expect(await balance(repository, '1121'), const Money(minorUnits: -500));
    expect(await balance(repository, '1140'), const Money(minorUnits: -500));
    expect(await balance(repository, '1150'), const Money(minorUnits: 300));
    expect(await balance(repository, '1170'), const Money(minorUnits: 200));
    expect(await balance(repository, '2110'), const Money(minorUnits: 1600));
    expect(await balance(repository, '2120'), const Money(minorUnits: 100));
    expect(await balance(repository, '4100'), const Money(minorUnits: 3000));
    expect(await balance(repository, '5100'), const Money(minorUnits: 1600));

    final repairValue = repair();
    final repairAdvance = RepairPayment(
      id: 'repair-advance-1',
      storeId: context.storeId,
      repairId: repairValue.id,
      customerId: repairValue.customerId,
      idempotencyKey: const IdempotencyKey('repair-advance-1'),
      postedAt: postedAt,
      kind: RepairPaymentKind.advance,
      paymentMethod: PartyPaymentMethod.cash,
      amount: const Money(minorUnits: 1000, currency: 'ILS'),
    );
    final repairPayload = RepairCommandMapper.createRequest(repairValue);
    final repairPaymentPayload = RepairCommandMapper.paymentRequest(
      payment: repairAdvance,
      accounts: const RepairPostingAccounts(),
    );
    final deliveryPayload = RepairCommandMapper.deliverRequest(
      storeId: context.storeId,
      repairId: repairValue.id,
      idempotencyKey: 'repair-delivery-1',
      postedAt: postedAt,
      accounts: const RepairPostingAccounts(),
    );

    expect(
      repairValue.finalCost,
      const Money(minorUnits: 4875, currency: 'ILS'),
    );
    expect(repairPayload['storeId'], context.storeId);
    expect(
      (repairPayload['repair'] as Map<String, dynamic>)['id'],
      repairValue.id,
    );
    expect(repairPaymentPayload['storeId'], context.storeId);
    expect(repairPaymentPayload['repairId'], repairValue.id);
    final repairPaymentData =
        repairPaymentPayload['payment'] as Map<String, dynamic>;
    expect(repairPaymentData['amountMinorUnits'], 1000);
    expect(deliveryPayload['storeId'], context.storeId);
    expect(deliveryPayload['repairId'], repairValue.id);

    await post(repository, salePlan.journalEntry);
    expect(await balance(repository, '1110'), const Money(minorUnits: 3600));
  });

  test(
    'rejects a foreign-store sale before it can enter the clean store ledger',
    () {
    final result = const SalePostingPlanner().prepare(
      context: context,
      sale: sale(storeId: 'store-b', id: 'foreign-sale-1'),
      accounts: const SalePostingAccounts(
        settlementAccountId: '1110',
        salesAccountId: '4100',
        inventoryAccountId: '1150',
        costOfSalesAccountId: '5100',
      ),
    );

    expect(result, isA<FailureResult<SalePostingPlan>>());
  });
}
