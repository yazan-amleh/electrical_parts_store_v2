import '../../../../core/idempotency/idempotency_key.dart';
import '../../../../core/money/money.dart';
import '../../../../core/tenancy/store_context.dart';
import '../enums/sale_payment_method.dart';
import 'sale_line.dart';

class Sale {
  Sale({
    required this.id,
    required this.storeId,
    required this.idempotencyKey,
    required this.postedAt,
    required this.paymentMethod,
    required List<SaleLine> lines,
    required this.tax,
    this.customerId,
    this.description,
  })  : postedAt = postedAt.toUtc(),
        lines = List.unmodifiable(lines) {
    _ensureSafeIdentifier(id, 'Sale id');
    if (storeId.trim().isEmpty) {
      throw ArgumentError('Sale store id is required.');
    }
    if (idempotencyKey.value.contains('/')) {
      throw ArgumentError('Sale idempotency key cannot contain a slash.');
    }
    if (this.lines.isEmpty) {
      throw ArgumentError('A sale requires at least one line.');
    }
    if (tax.isNegative) {
      throw ArgumentError('Sale tax cannot be negative.');
    }

    final saleCurrency = this.lines.first.currency;
    if (tax.currency != saleCurrency) {
      throw ArgumentError('Sale amounts must use one currency.');
    }
    for (final line in this.lines) {
      if (line.currency != saleCurrency) {
        throw ArgumentError('All sale lines must use one currency.');
      }
    }

    if (paymentMethod == SalePaymentMethod.credit &&
        (customerId == null || customerId!.trim().isEmpty)) {
      throw ArgumentError('A credit sale requires a customer.');
    }
    if (customerId != null && customerId!.contains('/')) {
      throw ArgumentError('Customer id cannot contain a slash.');
    }
    if (subtotal.isZero) {
      throw ArgumentError('A sale total must be greater than zero.');
    }
  }

  final String id;
  final String storeId;
  final IdempotencyKey idempotencyKey;
  final DateTime postedAt;
  final SalePaymentMethod paymentMethod;
  final List<SaleLine> lines;
  final Money tax;
  final String? customerId;
  final String? description;

  String get currency => lines.first.currency;

  Money get subtotal {
    return lines.fold(
      Money.zero(currency: currency),
      (sum, line) => sum + line.total,
    );
  }

  Money get grandTotal => subtotal + tax;

  Money get costTotal {
    return lines.fold(
      Money.zero(currency: currency),
      (sum, line) => sum + line.costTotal,
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
