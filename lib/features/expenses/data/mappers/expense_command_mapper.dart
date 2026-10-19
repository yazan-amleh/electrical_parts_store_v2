import '../../domain/entities/expense.dart';
import '../../domain/entities/expense_posting_plan.dart';

abstract final class ExpenseCommandMapper {
  static Map<String, dynamic> toRequest({
    required Expense expense,
    required ExpensePostingAccounts accounts,
  }) {
    return <String, dynamic>{
      'storeId': expense.storeId,
      'expense': <String, dynamic>{
        'id': expense.id,
        'idempotencyKey': expense.idempotencyKey.value,
        'postedAt': expense.postedAt.toUtc().toIso8601String(),
        'paymentMethod': expense.paymentMethod.name,
        'expenseAccountId': expense.expenseAccountId,
        'supplierId': expense.supplierId,
        'description': expense.description,
        'currency': expense.amount.currency,
        'amountMinorUnits': expense.amount.minorUnits,
        'taxMinorUnits': expense.tax.minorUnits,
      },
      'postingAccounts': <String, dynamic>{
        'settlementAccountId': accounts.settlementAccountId,
        'supplierPayableAccountId': accounts.supplierPayableAccountId,
        'inputTaxAccountId': accounts.inputTaxAccountId,
      },
    };
  }
}
