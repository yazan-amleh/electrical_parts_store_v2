import '../../../../core/idempotency/idempotency_key.dart';
import '../../../../core/money/money.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../features/accounting/domain/entities/journal_entry.dart';
import '../../../../features/inventory/domain/entities/inventory_movement.dart';
import 'sale.dart';

class SalePostingAccounts {
  const SalePostingAccounts({
    required this.settlementAccountId,
    required this.salesAccountId,
    required this.inventoryAccountId,
    required this.costOfSalesAccountId,
    this.taxAccountId,
  });

  final String settlementAccountId;
  final String salesAccountId;
  final String inventoryAccountId;
  final String costOfSalesAccountId;
  final String? taxAccountId;

  Iterable<String> get allAccountIds sync* {
    yield settlementAccountId;
    yield salesAccountId;
    yield inventoryAccountId;
    yield costOfSalesAccountId;
    if (taxAccountId != null) {
      yield taxAccountId!;
    }
  }

  void validate() {
    final accountIds = allAccountIds.toList(growable: false);
    if (accountIds.toSet().length != accountIds.length) {
      throw ArgumentError('Sale posting accounts must be distinct.');
    }

    for (final accountId in accountIds) {
      if (accountId.trim().isEmpty) {
        throw ArgumentError('Sale posting account id is required.');
      }
      if (accountId.contains('/')) {
        throw ArgumentError('Sale posting account id cannot contain a slash.');
      }
    }
  }
}

class SalePostingPlan {
  SalePostingPlan({
    required this.sale,
    required this.journalEntry,
    required List<InventoryMovement> inventoryMovements,
  }) : inventoryMovements = List.unmodifiable(inventoryMovements);

  final Sale sale;
  final JournalEntry journalEntry;
  final List<InventoryMovement> inventoryMovements;

  Money get totalCost => sale.costTotal;

  Quantity get totalIssuedQuantity {
    return inventoryMovements.fold(
      const Quantity.fromMilliUnits(0),
      (sum, movement) => sum + movement.quantityDelta,
    );
  }

  IdempotencyKey get idempotencyKey => sale.idempotencyKey;
}
