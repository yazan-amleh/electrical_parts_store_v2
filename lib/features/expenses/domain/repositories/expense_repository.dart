import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/expense.dart';
import '../entities/expense_posting_plan.dart';

abstract interface class ExpenseRepository {
  Future<Result<ExpensePostingPlan>> postExpense({
    required StoreContext context,
    required Expense expense,
    required ExpensePostingAccounts accounts,
  });
}
