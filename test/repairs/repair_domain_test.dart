import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/core/idempotency/idempotency_key.dart';
import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/core/quantity/quantity.dart';
import 'package:electrical_parts_store_v2/features/payments/domain/enums/party_payment_method.dart';
import 'package:electrical_parts_store_v2/features/repairs/domain/entities/repair_part.dart';
import 'package:electrical_parts_store_v2/features/repairs/domain/entities/repair_payment.dart';
import 'package:electrical_parts_store_v2/features/repairs/domain/entities/repair_posting_accounts.dart';
import 'package:electrical_parts_store_v2/features/repairs/domain/entities/repair_request.dart';
import 'package:electrical_parts_store_v2/features/repairs/domain/enums/repair_payment_kind.dart';

void main() {
  RepairRequest request() {
    return RepairRequest(
      id: 'repair-1',
      storeId: 'store-1',
      idempotencyKey: const IdempotencyKey('repair-1'),
      customerId: 'customer-1',
      deviceName: 'Inverter',
      deviceModel: 'INV-100',
      problemDescription: 'Does not start',
      createdAt: DateTime.utc(2026, 1, 1),
      receivedAt: DateTime.utc(2026, 1, 1),
      expectedDeliveryDate: DateTime.utc(2026, 1, 8),
      laborCost: const Money(minorUnits: 3000),
      parts: [
        RepairPart(
          id: 'part-1',
          productId: 'product-1',
          productName: 'Fuse',
          quantity: Quantity.fromMilliUnits(1500),
          unitPrice: const Money(minorUnits: 1250),
          unitCost: const Money(minorUnits: 700),
        ),
      ],
    );
  }

  test('repair totals use exact milli-to-minor rounding', () {
    final value = request();

    expect(value.partsTotal, const Money(minorUnits: 1875));
    expect(value.finalCost, const Money(minorUnits: 4875));
    expect(value.outstanding, const Money(minorUnits: 4875));
  });

  test('invoiced repairs calculate outstanding from the posted invoice', () {
    final value = request().copyWith(
      invoiceJournalEntryId: 'repair-1-invoice',
      invoicedTotal: const Money(minorUnits: 4500),
      paid: const Money(minorUnits: 1250),
    );

    expect(value.outstanding, const Money(minorUnits: 3250));
    expect(value.isInvoiced, isTrue);
    expect(value.isPaid, isFalse);
  });

  test('cheque advances are rejected until an invoice exists', () {
    expect(
      () => RepairPayment(
        id: 'payment-1',
        storeId: 'store-1',
        repairId: 'repair-1',
        customerId: 'customer-1',
        idempotencyKey: const IdempotencyKey('payment-1'),
        postedAt: DateTime.utc(2026, 1, 2),
        kind: RepairPaymentKind.advance,
        paymentMethod: PartyPaymentMethod.cheque,
        amount: const Money(minorUnits: 1000),
        chequeNumber: 'CHK-1',
        bankName: 'Bank',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('repair posting accounts have a distinct role for each control account', () {
    const accounts = RepairPostingAccounts();

    accounts.validate();
    expect(accounts.customerReceivableAccountId, '1140');
    expect(accounts.repairRevenueAccountId, '4110');
    expect(accounts.customerAdvancesAccountId, '2130');
  });
}
