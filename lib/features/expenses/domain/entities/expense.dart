import '../../../../core/idempotency/idempotency_key.dart';
import '../../../../core/money/money.dart';
import '../../../../core/tenancy/store_context.dart';
import '../enums/expense_payment_method.dart';

class Expense {
  Expense({
    required this.id,
    required this.storeId,
    required this.idempotencyKey,
    required DateTime postedAt,
    required this.paymentMethod,
    required this.expenseAccountId,
    required this.amount,
    required this.tax,
    this.supplierId,
    this.description,
  }) : postedAt = postedAt.toUtc() {
    _ensureSafeIdentifier(id, 'Expense id');
    _ensureSafeIdentifier(storeId, 'Store id');
    _ensureSafeIdentifier(expenseAccountId, 'Expense account id');

    if (idempotencyKey.value.contains('/')) {
      throw ArgumentError('Expense idempotency key cannot contain a slash.');
    }
    if (amount.isNegative || amount.isZero) {
      throw ArgumentError('Expense amount must be greater than zero.');
    }
    if (tax.isNegative) {
      throw ArgumentError('Expense tax cannot be negative.');
    }
    if (amount.currency != tax.currency) {
      throw ArgumentError('Expense amounts must use one currency.');
    }
    if (paymentMethod == ExpensePaymentMethod.credit &&
        (supplierId == null || supplierId!.trim().isEmpty)) {
      throw ArgumentError('A credit expense requires a supplier.');
    }
    if (supplierId != null && supplierId!.contains('/')) {
      throw ArgumentError('Supplier id cannot contain a slash.');
    }
  }

  final String id;
  final String storeId;
  final IdempotencyKey idempotencyKey;
  final DateTime postedAt;
  final ExpensePaymentMethod paymentMethod;
  final String expenseAccountId;
  final Money amount;
  final Money tax;
  final String? supplierId;
  final String? description;

  Money get total => amount + tax;

  String get sourceType => 'expense';

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
