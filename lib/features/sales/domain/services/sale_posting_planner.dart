import '../../../../core/errors/failure.dart';
import '../../../../core/idempotency/idempotency_key.dart';
import '../../../../core/money/money.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../accounting/domain/entities/journal_entry.dart';
import '../../../accounting/domain/entities/journal_line.dart';
import '../../../inventory/domain/entities/inventory_movement.dart';
import '../../../inventory/domain/enums/inventory_movement_type.dart';
import '../entities/sale.dart';
import '../entities/sale_posting_plan.dart';

class SalePostingPlanner {
  const SalePostingPlanner();

  Result<SalePostingPlan> prepare({
    required StoreContext context,
    required Sale sale,
    required SalePostingAccounts accounts,
  }) {
    if (sale.storeId != context.storeId) {
      return const FailureResult<SalePostingPlan>(
        AuthorizationFailure('Sale does not belong to the active store.'),
      );
    }

    try {
      accounts.validate();
      final settlementAccountId = accounts.accountFor(sale.paymentMethod);
      if (!sale.tax.isZero &&
          (accounts.taxAccountId == null ||
              accounts.taxAccountId!.trim().isEmpty)) {
        return const FailureResult<SalePostingPlan>(
          ValidationFailure('A tax account is required when tax is present.'),
        );
      }

      final zero = Money.zero(currency: sale.currency);
      final journalLines = <JournalLine>[
        JournalLine(
          id: _lineId(sale.id, 'settlement'),
          accountId: settlementAccountId,
          debit: sale.grandTotal,
          credit: zero,
          description: sale.paymentMethod.name,
        ),
        JournalLine(
          id: _lineId(sale.id, 'sales'),
          accountId: accounts.salesAccountId,
          debit: zero,
          credit: sale.subtotal,
          description: 'Sales revenue',
        ),
      ];

      if (!sale.tax.isZero) {
        journalLines.add(
          JournalLine(
            id: _lineId(sale.id, 'tax'),
            accountId: accounts.taxAccountId!,
            debit: zero,
            credit: sale.tax,
            description: 'Sales tax',
          ),
        );
      }

      if (!sale.costTotal.isZero) {
        journalLines.addAll(<JournalLine>[
          JournalLine(
            id: _lineId(sale.id, 'cost'),
            accountId: accounts.costOfSalesAccountId,
            debit: sale.costTotal,
            credit: zero,
            description: 'Cost of sales',
          ),
          JournalLine(
            id: _lineId(sale.id, 'inventory'),
            accountId: accounts.inventoryAccountId,
            debit: zero,
            credit: sale.costTotal,
            description: 'Inventory issue',
          ),
        ]);
      }

      final entry = JournalEntry(
        id: _lineId(sale.id, 'journal'),
        storeId: sale.storeId,
        idempotencyKey: _scopeKey(sale.idempotencyKey.value, 'journal'),
        postedAt: sale.postedAt,
        sourceType: 'sale',
        description: sale.description,
        lines: journalLines,
      );

      final movements = sale.lines
          .where((line) => !line.isService)
          .map(
            (line) => InventoryMovement(
              id: _movementId(sale.id, line.id),
              storeId: sale.storeId,
              productId: line.productId,
              type: InventoryMovementType.saleIssue,
              quantityDelta: Quantity.fromMilliUnits(
                -line.baseQuantity.milliUnits,
              ),
              unitCost: line.unitCost,
              totalCost: line.costTotal,
              idempotencyKey: IdempotencyKey(
                _lineScopeKey(sale.idempotencyKey.value, line.id),
              ),
              sourceType: 'sale',
              sourceId: sale.id,
              occurredAt: sale.postedAt,
            ),
          )
          .toList(growable: false);

      return Success(
        SalePostingPlan(
          sale: sale,
          journalEntry: entry,
          inventoryMovements: movements,
        ),
      );
    } on ArgumentError catch (error) {
      return FailureResult<SalePostingPlan>(
        ValidationFailure(error.message.toString()),
      );
    }
  }

  static String _lineId(String saleId, String suffix) {
    return '$saleId-$suffix';
  }

  static String _movementId(String saleId, String lineId) {
    return '$saleId-inventory-$lineId';
  }

  static String _scopeKey(String key, String scope) {
    return '$key:$scope';
  }

  static String _lineScopeKey(String key, String lineId) {
    return '$key:inventory:$lineId';
  }
}
