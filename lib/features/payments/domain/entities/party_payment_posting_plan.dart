import '../../../../core/idempotency/idempotency_key.dart';
import '../../../accounting/domain/entities/journal_entry.dart';
import '../../../parties/domain/entities/party_ledger_entry.dart';
import 'party_payment.dart';

class PartyPaymentPostingAccounts {
  const PartyPaymentPostingAccounts({
    required this.settlementAccountId,
    required this.partyAccountId,
  });

  final String settlementAccountId;
  final String partyAccountId;

  Iterable<String> get allAccountIds sync* {
    yield settlementAccountId;
    yield partyAccountId;
  }

  void validate() {
    final accountIds = allAccountIds.toList(growable: false);
    if (accountIds.toSet().length != accountIds.length) {
      throw ArgumentError('Party payment accounts must be distinct.');
    }

    for (final accountId in accountIds) {
      if (accountId.trim().isEmpty) {
        throw ArgumentError('Party payment account id is required.');
      }
      if (accountId.contains('/')) {
        throw ArgumentError(
          'Party payment account id cannot contain a slash.',
        );
      }
    }
  }
}

class PartyPaymentPostingPlan {
  const PartyPaymentPostingPlan({
    required this.payment,
    required this.journalEntry,
    required this.partyLedgerEntry,
  });

  final PartyPayment payment;
  final JournalEntry journalEntry;
  final PartyLedgerEntry partyLedgerEntry;

  IdempotencyKey get idempotencyKey => payment.idempotencyKey;
}
