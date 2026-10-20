import '../../../../core/errors/failure.dart';
import '../../../../core/idempotency/idempotency_key.dart';
import '../../../../core/money/money.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../accounting/domain/entities/journal_entry.dart';
import '../../../accounting/domain/entities/journal_line.dart';
import '../../../inventory/domain/entities/inventory_movement.dart';
import '../../../inventory/domain/enums/inventory_movement_type.dart';
import '../entities/purchase.dart';
import '../entities/purchase_posting_plan.dart';

class PurchasePostingPlanner {
  const PurchasePostingPlanner();

  Result<PurchasePostingPlan> prepare({
    required StoreContext context,
    required Purchase purchase,
    required PurchasePostingAccounts accounts,
  }) {
    if (purchase.storeId != context.storeId) {
      return const FailureResult<PurchasePostingPlan>(
        AuthorizationFailure('Purchase does not belong to the active store.'),
      );
    }

    try {
      accounts.validate();
      accounts.accountFor(purchase.paymentMethod);
      accounts.validateTax(purchase.tax);

      final zero = Money.zero(currency: purchase.currency);
      final creditAccountId = accounts.accountFor(purchase.paymentMethod);
      final journalLines = <JournalLine>[
        JournalLine(
          id: _lineId(purchase.id, 'inventory'),
          accountId: accounts.inventoryAccountId,
          debit: purchase.subtotal,
          credit: zero,
          description: 'Inventory receipt',
        ),
      ];

      if (!purchase.tax.isZero) {
        journalLines.add(
          JournalLine(
            id: _lineId(purchase.id, 'input-tax'),
            accountId: accounts.inputTaxAccountId!,
            debit: purchase.tax,
            credit: zero,
            description: 'Input tax',
          ),
        );
      }

      journalLines.add(
        JournalLine(
          id: _lineId(purchase.id, 'settlement'),
          accountId: creditAccountId,
          debit: zero,
          credit: purchase.grandTotal,
          description: purchase.paymentMethod.name,
        ),
      );

      final entry = JournalEntry(
        id: _lineId(purchase.id, 'journal'),
        storeId: purchase.storeId,
        idempotencyKey: _scopeKey(purchase.idempotencyKey.value, 'journal'),
        postedAt: purchase.postedAt,
        sourceType: 'purchase',
        description: purchase.description,
        lines: journalLines,
      );

      final movements = purchase.lines
          .map(
            (line) => InventoryMovement(
              id: _movementId(purchase.id, line.id),
              storeId: purchase.storeId,
              productId: line.productId,
              type: InventoryMovementType.purchaseReceipt,
              quantityDelta: line.baseQuantity,
              unitCost: line.unitCost,
              totalCost: line.total,
              idempotencyKey: IdempotencyKey(
                _lineScopeKey(purchase.idempotencyKey.value, line.id),
              ),
              sourceType: 'purchase',
              sourceId: purchase.id,
              occurredAt: purchase.postedAt,
            ),
          )
          .toList(growable: false);

      return Success(
        PurchasePostingPlan(
          purchase: purchase,
          journalEntry: entry,
          inventoryMovements: movements,
        ),
      );
    } on ArgumentError catch (error) {
      return FailureResult<PurchasePostingPlan>(
        ValidationFailure(error.message.toString()),
      );
    }
  }

  static String _lineId(String purchaseId, String suffix) {
    return '$purchaseId-$suffix';
  }

  static String _movementId(String purchaseId, String lineId) {
    return '$purchaseId-inventory-$lineId';
  }

  static String _scopeKey(String key, String scope) {
    return '$key:$scope';
  }

  static String _lineScopeKey(String key, String lineId) {
    return '$key:inventory:$lineId';
  }
}
