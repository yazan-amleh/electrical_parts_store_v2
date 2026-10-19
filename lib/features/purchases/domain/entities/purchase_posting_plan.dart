import '../../../../core/idempotency/idempotency_key.dart';
import '../../../../core/money/money.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../accounting/domain/entities/journal_entry.dart';
import '../../../inventory/domain/entities/inventory_movement.dart';
import '../enums/purchase_payment_method.dart';
import 'purchase.dart';

class PurchasePostingAccounts {
  const PurchasePostingAccounts({
    this.settlementAccountId,
    required this.inventoryAccountId,
    this.supplierPayableAccountId,
    this.inputTaxAccountId,
  });

  final String? settlementAccountId;
  final String inventoryAccountId;
  final String? supplierPayableAccountId;
  final String? inputTaxAccountId;

  Iterable<String> get allAccountIds sync* {
    if (settlementAccountId != null) {
      yield settlementAccountId!;
    }
    yield inventoryAccountId;
    if (supplierPayableAccountId != null) {
      yield supplierPayableAccountId!;
    }
    if (inputTaxAccountId != null) {
      yield inputTaxAccountId!;
    }
  }

  void validate() {
    final accountIds = allAccountIds.toList(growable: false);
    if (accountIds.toSet().length != accountIds.length) {
      throw ArgumentError('Purchase posting accounts must be distinct.');
    }

    for (final accountId in accountIds) {
      if (accountId.trim().isEmpty) {
        throw ArgumentError('Purchase posting account id is required.');
      }
      if (accountId.contains('/')) {
        throw ArgumentError(
          'Purchase posting account id cannot contain a slash.',
        );
      }
    }
  }

  String accountFor(PurchasePaymentMethod paymentMethod) {
    if (paymentMethod == PurchasePaymentMethod.credit) {
      final accountId = supplierPayableAccountId;
      if (accountId == null || accountId.trim().isEmpty) {
        throw ArgumentError(
          'A supplier payable account is required for credit purchases.',
        );
      }
      return accountId;
    }

    final accountId = settlementAccountId;
    if (accountId == null || accountId.trim().isEmpty) {
      throw ArgumentError(
        'A settlement account is required for paid purchases.',
      );
    }
    return accountId;
  }

  void validateTax(Money tax) {
    if (tax.isZero) {
      return;
    }
    final accountId = inputTaxAccountId;
    if (accountId == null || accountId.trim().isEmpty) {
      throw ArgumentError(
        'An input tax account is required when tax is present.',
      );
    }
  }
}

class PurchasePostingPlan {
  PurchasePostingPlan({
    required this.purchase,
    required this.journalEntry,
    required List<InventoryMovement> inventoryMovements,
  }) : inventoryMovements = List.unmodifiable(inventoryMovements);

  final Purchase purchase;
  final JournalEntry journalEntry;
  final List<InventoryMovement> inventoryMovements;

  Money get totalCost => purchase.subtotal;

  Quantity get totalReceivedQuantity {
    return inventoryMovements.fold(
      const Quantity.fromMilliUnits(0),
      (sum, movement) => sum + movement.quantityDelta,
    );
  }

  IdempotencyKey get idempotencyKey => purchase.idempotencyKey;
}
