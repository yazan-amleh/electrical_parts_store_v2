import '../../../../core/money/money.dart';
import '../enums/party_type.dart';

class PartyLedgerEntry {
  PartyLedgerEntry({
    required this.id,
    required this.storeId,
    required this.partyType,
    required this.partyId,
    required this.sourceType,
    required this.sourceId,
    required this.postedAt,
    required this.debit,
    required this.credit,
    this.description,
  }) : postedAt = postedAt.toUtc() {
    _ensureSafeIdentifier(id, 'Party ledger entry id');
    _ensureSafeIdentifier(storeId, 'Store id');
    _ensureSafeIdentifier(partyId, 'Party id');
    _ensureSafeIdentifier(sourceId, 'Source id');

    if (sourceType.trim().isEmpty) {
      throw ArgumentError('Party ledger source type is required.');
    }
    if (debit.isNegative || credit.isNegative) {
      throw ArgumentError('Party ledger amounts cannot be negative.');
    }
    if (debit.currency != credit.currency) {
      throw ArgumentError('Party ledger amounts must use one currency.');
    }
    if (debit.isZero == credit.isZero) {
      throw ArgumentError(
        'A party ledger entry must contain exactly one side.',
      );
    }
  }

  final String id;
  final String storeId;
  final PartyType partyType;
  final String partyId;
  final String sourceType;
  final String sourceId;
  final DateTime postedAt;
  final Money debit;
  final Money credit;
  final String? description;

  Money get balanceDelta => debit - credit;

  static void _ensureSafeIdentifier(String value, String label) {
    if (value.trim().isEmpty) {
      throw ArgumentError('$label is required.');
    }
    if (value.contains('/')) {
      throw ArgumentError('$label cannot contain a slash.');
    }
  }
}
