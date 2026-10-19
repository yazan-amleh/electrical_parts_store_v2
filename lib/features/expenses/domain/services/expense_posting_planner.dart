import '../../../../core/errors/failure.dart';
import '../../../../core/idempotency/idempotency_key.dart';
import '../../../../core/money/money.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../accounting/domain/entities/journal_entry.dart';
import '../../../accounting/domain/entities/journal_line.dart';
import '../../../parties/domain/entities/party_ledger_entry.dart';
import '../../../parties/domain/enums/party_type.dart';
import '../entities/expense.dart';
import '../enums/expense_payment_method.dart';
import '../entities/expense_posting_plan.dart';

class ExpensePostingPlanner {
  const ExpensePostingPlanner();

  Result<ExpensePostingPlan> prepare({
    required StoreContext context,
    required Expense expense,
    required ExpensePostingAccounts accounts,
  }) {
    if (expense.storeId != context.storeId) {
      return const FailureResult<ExpensePostingPlan>(
        AuthorizationFailure(
          'Expense does not belong to the active store.',
        ),
      );
    }

    try {
      accounts.validate();
      final paymentAccountId = accounts.accountFor(expense.paymentMethod);
      accounts.validateTax(expense.tax.minorUnits);

      final zero = Money.zero(currency: expense.amount.currency);
      final journalLines = <JournalLine>[
        JournalLine(
          id: _lineId(expense.id, 'expense'),
          accountId: expense.expenseAccountId,
          debit: expense.amount,
          credit: zero,
          description: 'Operating expense',
        ),
      ];

      if (!expense.tax.isZero) {
        journalLines.add(
          JournalLine(
            id: _lineId(expense.id, 'input-tax'),
            accountId: accounts.inputTaxAccountId!,
            debit: expense.tax,
            credit: zero,
            description: 'Input tax',
          ),
        );
      }

      journalLines.add(
        JournalLine(
          id: _lineId(expense.id, 'payment'),
          accountId: paymentAccountId,
          debit: zero,
          credit: expense.total,
          description: expense.paymentMethod.name,
        ),
      );

      final entry = JournalEntry(
        id: _lineId(expense.id, 'journal'),
        storeId: expense.storeId,
        idempotencyKey: _scopeKey(
          expense.idempotencyKey.value,
          'journal',
        ),
        postedAt: expense.postedAt,
        sourceType: expense.sourceType,
        description: expense.description,
        lines: journalLines,
      );

      PartyLedgerEntry? partyLedgerEntry;
      if (expense.paymentMethod == ExpensePaymentMethod.credit) {
        partyLedgerEntry = PartyLedgerEntry(
          id: _lineId(expense.id, PartyType.supplier.name),
          storeId: expense.storeId,
          partyType: PartyType.supplier,
          partyId: expense.supplierId!,
          sourceType: expense.sourceType,
          sourceId: expense.id,
          postedAt: expense.postedAt,
          debit: zero,
          credit: expense.total,
          description: expense.description,
        );
      }

      return Success<ExpensePostingPlan>(
        ExpensePostingPlan(
          expense: expense,
          journalEntry: entry,
          partyLedgerEntry: partyLedgerEntry,
        ),
      );
    } on ArgumentError catch (error) {
      return FailureResult<ExpensePostingPlan>(
        ValidationFailure(error.message.toString()),
      );
    }
  }

  static String _lineId(String expenseId, String suffix) {
    return '$expenseId-$suffix';
  }

  static String _scopeKey(String key, String scope) {
    return '$key:$scope';
  }
}
