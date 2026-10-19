import '../../../../core/idempotency/idempotency_key.dart';
import '../../../accounting/domain/entities/journal_entry.dart';
import '../../../parties/domain/entities/party_ledger_entry.dart';
import '../enums/expense_payment_method.dart';
import 'expense.dart';

class ExpensePostingAccounts {
  const ExpensePostingAccounts({
    this.settlementAccountId,
    this.supplierPayableAccountId,
    this.inputTaxAccountId,
  });

  final String? settlementAccountId;
  final String? supplierPayableAccountId;
  final String? inputTaxAccountId;

  Iterable<String> get allAccountIds sync* {
    if (settlementAccountId != null) {
      yield settlementAccountId!;
    }
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
      throw ArgumentError('Expense posting accounts must be distinct.');
    }

    for (final accountId in accountIds) {
      if (accountId.trim().isEmpty) {
        throw ArgumentError('Expense posting account id is required.');
      }
      if (accountId.contains('/')) {
        throw ArgumentError(
          'Expense posting account id cannot contain a slash.',
        );
      }
    }
  }

  String accountFor(ExpensePaymentMethod paymentMethod) {
    if (paymentMethod == ExpensePaymentMethod.credit) {
      final accountId = supplierPayableAccountId;
      if (accountId == null || accountId.trim().isEmpty) {
        throw ArgumentError(
          'A supplier payable account is required for credit expenses.',
        );
      }
      return accountId;
    }

    final accountId = settlementAccountId;
    if (accountId == null || accountId.trim().isEmpty) {
      throw ArgumentError(
        'A settlement account is required for paid expenses.',
      );
    }
    return accountId;
  }

  void validateTax(int taxMinorUnits) {
    if (taxMinorUnits < 0) {
      throw ArgumentError('Expense tax cannot be negative.');
    }
    if (taxMinorUnits > 0 &&
        (inputTaxAccountId == null || inputTaxAccountId!.trim().isEmpty)) {
      throw ArgumentError(
        'An input tax account is required when tax is present.',
      );
    }
  }
}

class ExpensePostingPlan {
  const ExpensePostingPlan({
    required this.expense,
    required this.journalEntry,
    this.partyLedgerEntry,
  });

  final Expense expense;
  final JournalEntry journalEntry;
  final PartyLedgerEntry? partyLedgerEntry;

  IdempotencyKey get idempotencyKey => expense.idempotencyKey;
}
