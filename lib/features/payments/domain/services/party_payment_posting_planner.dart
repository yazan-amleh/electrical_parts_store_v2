import '../../../../core/errors/failure.dart';
import '../../../../core/money/money.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../accounting/domain/entities/journal_entry.dart';
import '../../../accounting/domain/entities/journal_line.dart';
import '../../../parties/domain/entities/party_ledger_entry.dart';
import '../../../parties/domain/enums/party_type.dart';
import '../entities/party_payment.dart';
import '../entities/party_payment_posting_plan.dart';

class PartyPaymentPostingPlanner {
  const PartyPaymentPostingPlanner();

  Result<PartyPaymentPostingPlan> prepare({
    required StoreContext context,
    required PartyPayment payment,
    required PartyPaymentPostingAccounts accounts,
  }) {
    if (payment.storeId != context.storeId) {
      return const FailureResult<PartyPaymentPostingPlan>(
        AuthorizationFailure(
          'Party payment does not belong to the active store.',
        ),
      );
    }

    try {
      accounts.validate();

      final zero = Money.zero(currency: payment.amount.currency);
      final isCustomer = payment.partyType == PartyType.customer;
      final journalLines = <JournalLine>[
        JournalLine(
          id: _lineId(payment.id, 'settlement'),
          accountId: accounts.settlementAccountId,
          debit: isCustomer ? payment.amount : zero,
          credit: isCustomer ? zero : payment.amount,
          description: payment.paymentMethod.name,
        ),
        JournalLine(
          id: _lineId(payment.id, 'party'),
          accountId: accounts.partyAccountId,
          debit: isCustomer ? zero : payment.amount,
          credit: isCustomer ? payment.amount : zero,
          description: payment.sourceType,
        ),
      ];

      final entry = JournalEntry(
        id: _lineId(payment.id, 'journal'),
        storeId: payment.storeId,
        idempotencyKey: _scopeKey(payment.idempotencyKey.value, 'journal'),
        postedAt: payment.postedAt,
        sourceType: payment.sourceType,
        description: payment.description,
        lines: journalLines,
      );

      final partyLedgerEntry = PartyLedgerEntry(
        id: _lineId(payment.id, payment.partyType.name),
        storeId: payment.storeId,
        partyType: payment.partyType,
        partyId: payment.partyId,
        sourceType: payment.sourceType,
        sourceId: payment.id,
        postedAt: payment.postedAt,
        debit: isCustomer ? zero : payment.amount,
        credit: isCustomer ? payment.amount : zero,
        description: payment.description,
      );

      return Success<PartyPaymentPostingPlan>(
        PartyPaymentPostingPlan(
          payment: payment,
          journalEntry: entry,
          partyLedgerEntry: partyLedgerEntry,
        ),
      );
    } on ArgumentError catch (error) {
      return FailureResult<PartyPaymentPostingPlan>(
        ValidationFailure(error.message.toString()),
      );
    }
  }

  static String _lineId(String paymentId, String suffix) {
    return '$paymentId-$suffix';
  }

  static String _scopeKey(String key, String scope) {
    return '$key:$scope';
  }
}
