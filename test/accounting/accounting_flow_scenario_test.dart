import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/accounting/data/repositories/in_memory_accounting_repository.dart';
import 'package:electrical_parts_store_v2/features/accounting/domain/entities/account.dart';
import 'package:electrical_parts_store_v2/features/accounting/domain/entities/journal_entry.dart';
import 'package:electrical_parts_store_v2/features/accounting/domain/entities/journal_line.dart';
import 'package:electrical_parts_store_v2/features/accounting/domain/enums/accounting_enums.dart';

void main() {
  const context = StoreContext(storeId: 'store-1', userId: 'user-1');

  final accounts = <Account>[
    const Account(
      id: 'cash',
      storeId: 'store-1',
      code: '1110',
      name: 'الصندوق',
      type: AccountType.asset,
      normalSide: NormalSide.debit,
      controlType: ControlType.cashBox,
      statementSection: StatementSection.currentAsset,
    ),
    const Account(
      id: 'bank',
      storeId: 'store-1',
      code: '1120',
      name: 'البنك',
      type: AccountType.asset,
      normalSide: NormalSide.debit,
      controlType: ControlType.bank,
      statementSection: StatementSection.currentAsset,
    ),
    const Account(
      id: 'receivable',
      storeId: 'store-1',
      code: '1140',
      name: 'ذمم العملاء',
      type: AccountType.asset,
      normalSide: NormalSide.debit,
      controlType: ControlType.customerReceivable,
      statementSection: StatementSection.currentAsset,
    ),
    const Account(
      id: 'inventory',
      storeId: 'store-1',
      code: '1150',
      name: 'المخزون',
      type: AccountType.asset,
      normalSide: NormalSide.debit,
      controlType: ControlType.inventory,
      statementSection: StatementSection.currentAsset,
    ),
    const Account(
      id: 'payable',
      storeId: 'store-1',
      code: '2110',
      name: 'ذمم الموردين',
      type: AccountType.liability,
      normalSide: NormalSide.credit,
      controlType: ControlType.supplierPayable,
      statementSection: StatementSection.currentLiability,
    ),
    const Account(
      id: 'sales',
      storeId: 'store-1',
      code: '4100',
      name: 'المبيعات',
      type: AccountType.revenue,
      normalSide: NormalSide.credit,
      controlType: ControlType.none,
      statementSection: StatementSection.revenue,
    ),
    const Account(
      id: 'cost',
      storeId: 'store-1',
      code: '5100',
      name: 'تكلفة المبيعات',
      type: AccountType.expense,
      normalSide: NormalSide.debit,
      controlType: ControlType.none,
      statementSection: StatementSection.costOfSales,
    ),
  ];

  JournalEntry entry({
    required String id,
    required String sourceType,
    required List<JournalLine> lines,
  }) {
    return JournalEntry(
      id: id,
      storeId: context.storeId,
      idempotencyKey: '$sourceType-$id',
      postedAt: DateTime.utc(2026, 1, 1),
      sourceType: sourceType,
      lines: lines,
    );
  }

  JournalLine debit(String id, String accountId, int minorUnits) {
    return JournalLine(
      id: id,
      accountId: accountId,
      debit: Money(minorUnits: minorUnits),
      credit: const Money.zero(),
    );
  }

  JournalLine credit(String id, String accountId, int minorUnits) {
    return JournalLine(
      id: id,
      accountId: accountId,
      debit: const Money.zero(),
      credit: Money(minorUnits: minorUnits),
    );
  }

  Future<void> post(
    InMemoryAccountingRepository repository,
    JournalEntry value,
  ) async {
    final result = await repository.postJournalEntry(
      context: context,
      entry: value,
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

  test('keeps cash, bank, parties and inventory separate through a full flow',
      () async {
    final repository = InMemoryAccountingRepository(accounts: accounts);

    await post(
      repository,
      entry(
        id: 'purchase-1',
        sourceType: 'purchase',
        lines: [
          debit('purchase-inventory', 'inventory', 8000),
          credit('purchase-payable', 'payable', 8000),
        ],
      ),
    );
    await post(
      repository,
      entry(
        id: 'supplier-payment-1',
        sourceType: 'party-payment',
        lines: [
          debit('supplier-payment-payable', 'payable', 3000),
          credit('supplier-payment-cash', 'cash', 3000),
        ],
      ),
    );
    await post(
      repository,
      entry(
        id: 'sale-1',
        sourceType: 'sale',
        lines: [
          debit('sale-receivable', 'receivable', 12000),
          credit('sale-revenue', 'sales', 12000),
          debit('sale-cost', 'cost', 5000),
          credit('sale-inventory', 'inventory', 5000),
        ],
      ),
    );
    await post(
      repository,
      entry(
        id: 'customer-receipt-1',
        sourceType: 'party-payment',
        lines: [
          debit('customer-receipt-cash', 'cash', 7000),
          credit('customer-receipt-receivable', 'receivable', 7000),
        ],
      ),
    );
    await post(
      repository,
      entry(
        id: 'transfer-1',
        sourceType: 'account-transfer',
        lines: [
          debit('transfer-bank', 'bank', 2000),
          credit('transfer-cash', 'cash', 2000),
        ],
      ),
    );

    expect(
        await balance(repository, 'inventory'), const Money(minorUnits: 3000));
    expect(await balance(repository, 'payable'), const Money(minorUnits: 5000));
    expect(
      await balance(repository, 'receivable'),
      const Money(minorUnits: 5000),
    );
    expect(await balance(repository, 'cash'), const Money(minorUnits: 2000));
    expect(await balance(repository, 'bank'), const Money(minorUnits: 2000));
    expect(await balance(repository, 'sales'), const Money(minorUnits: 12000));
    expect(await balance(repository, 'cost'), const Money(minorUnits: 5000));
  });

  test('replaying one command does not duplicate its balance delta', () async {
    final repository = InMemoryAccountingRepository(accounts: accounts);
    final value = entry(
      id: 'cash-sale-1',
      sourceType: 'sale',
      lines: [
        debit('cash-sale-cash', 'cash', 4500),
        credit('cash-sale-revenue', 'sales', 4500),
      ],
    );

    await post(repository, value);
    await post(repository, value);

    expect(await balance(repository, 'cash'), const Money(minorUnits: 4500));
    expect(await balance(repository, 'sales'), const Money(minorUnits: 4500));
  });
}
