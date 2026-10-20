import '../../../../core/idempotency/idempotency_key.dart';
import '../../../../core/money/money.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../accounting/domain/entities/journal_entry.dart';
import '../../../inventory/domain/entities/inventory_movement.dart';
import '../enums/sale_payment_method.dart';
import 'sale.dart';

class SalePostingAccounts {
  const SalePostingAccounts({
    this.settlementAccountId,
    this.customerReceivableAccountId,
    required this.salesAccountId,
    required this.inventoryAccountId,
    required this.costOfSalesAccountId,
    this.taxAccountId,
  });

  final String? settlementAccountId;
  final String? customerReceivableAccountId;
  final String salesAccountId;
  final String inventoryAccountId;
  final String costOfSalesAccountId;
  final String? taxAccountId;

  Iterable<String> get allAccountIds sync* {
    if (settlementAccountId != null) {
      yield settlementAccountId!;
    }
    if (customerReceivableAccountId != null) {
      yield customerReceivableAccountId!;
    }
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

  String accountFor(SalePaymentMethod paymentMethod) {
    if (paymentMethod == SalePaymentMethod.credit) {
      final accountId = customerReceivableAccountId;
      if (accountId == null || accountId.trim().isEmpty) {
        throw ArgumentError(
          'A customer receivable account is required for credit sales.',
        );
      }
      return accountId;
    }

    final accountId = settlementAccountId;
    if (accountId == null || accountId.trim().isEmpty) {
      throw ArgumentError('A settlement account is required for paid sales.');
    }
    return accountId;
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
