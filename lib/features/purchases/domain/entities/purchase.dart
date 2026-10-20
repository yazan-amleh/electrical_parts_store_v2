import '../../../../core/idempotency/idempotency_key.dart';
import '../../../../core/money/money.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/tenancy/store_context.dart';
import '../enums/purchase_payment_method.dart';
import 'purchase_line.dart';

class Purchase {
  Purchase({
    required this.id,
    required this.storeId,
    required this.idempotencyKey,
    required DateTime postedAt,
    required this.paymentMethod,
    required List<PurchaseLine> lines,
    required this.tax,
    this.supplierId,
    this.description,
  })  : postedAt = postedAt.toUtc(),
        lines = List.unmodifiable(lines) {
    _ensureSafeIdentifier(id, 'Purchase id');
    if (storeId.trim().isEmpty) {
      throw ArgumentError('Purchase store id is required.');
    }
    if (idempotencyKey.value.contains('/')) {
      throw ArgumentError('Purchase idempotency key cannot contain a slash.');
    }
    if (this.lines.isEmpty) {
      throw ArgumentError('A purchase requires at least one line.');
    }
    if (tax.isNegative) {
      throw ArgumentError('Purchase tax cannot be negative.');
    }

    final lineIds = this.lines.map((line) => line.id).toSet();
    if (lineIds.length != this.lines.length) {
      throw ArgumentError('Purchase line ids must be unique.');
    }

    final purchaseCurrency = this.lines.first.currency;
    if (tax.currency != purchaseCurrency) {
      throw ArgumentError('Purchase amounts must use one currency.');
    }
    for (final line in this.lines) {
      if (line.currency != purchaseCurrency) {
        throw ArgumentError('All purchase lines must use one currency.');
      }
    }

    if (paymentMethod == PurchasePaymentMethod.credit &&
        (supplierId == null || supplierId!.trim().isEmpty)) {
      throw ArgumentError('A credit purchase requires a supplier.');
    }
    if (supplierId != null && supplierId!.contains('/')) {
      throw ArgumentError('Supplier id cannot contain a slash.');
    }
    if (subtotal.isZero) {
      throw ArgumentError('A purchase total must be greater than zero.');
    }
  }

  final String id;
  final String storeId;
  final IdempotencyKey idempotencyKey;
  final DateTime postedAt;
  final PurchasePaymentMethod paymentMethod;
  final List<PurchaseLine> lines;
  final Money tax;
  final String? supplierId;
  final String? description;

  String get currency => lines.first.currency;

  Money get subtotal {
    return lines.fold(
      Money.zero(currency: currency),
      (sum, line) => sum + line.total,
    );
  }

  Money get grandTotal => subtotal + tax;

  Quantity get totalReceivedQuantity {
    return lines.fold(
      const Quantity.fromMilliUnits(0),
      (sum, line) => sum + line.baseQuantity,
    );
  }

  StoreContext contextFor(String userId) {
    return StoreContext(storeId: storeId, userId: userId);
  }

  static void _ensureSafeIdentifier(String value, String label) {
    if (value.trim().isEmpty) {
      throw ArgumentError('$label is required.');
    }
    if (value.contains('/')) {
      throw ArgumentError('$label cannot contain a slash.');
    }
  }
}
