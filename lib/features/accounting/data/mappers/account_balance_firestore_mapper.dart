import '../../../../core/money/money.dart';
import '../../domain/entities/account_balance_snapshot.dart';

/// Fail-closed decoder for a derived general-ledger balance projection.
/// A missing balance document is a genuine zero before any posting, but an
/// existing malformed document is NEVER zeroed or silently skipped.
abstract final class AccountBalanceFirestoreMapper {
  static const int maxSafeMinorUnits = 9007199254740991;

  static AccountBalanceSnapshot fromMap({
    required Map<String, dynamic> data,
    required String documentAccountId,
    required String expectedStoreId,
  }) {
    if (data['storeId'] != expectedStoreId ||
        data['accountId'] != documentAccountId) {
      throw FormatException(
        'Account balance identity does not match its store/document path: '
        '$documentAccountId',
      );
    }

    final currency = data['currency'];
    if (currency is! String || currency.trim().isEmpty) {
      throw FormatException('Account balance currency is missing: '
          '$documentAccountId');
    }

    final debit = _minor(data['debitMinorUnits'], 'debit', documentAccountId);
    final credit = _minor(data['creditMinorUnits'], 'credit', documentAccountId);
    final net = _minor(
      data['balanceMinorUnits'],
      'net balance',
      documentAccountId,
      allowNegative: true,
    );
    if (net != debit - credit) {
      throw FormatException(
        'Account balance projection does not reconcile: $documentAccountId',
      );
    }
    return AccountBalanceSnapshot(
      accountId: documentAccountId,
      debit: Money(minorUnits: debit, currency: currency),
      credit: Money(minorUnits: credit, currency: currency),
    );
  }

  static int _minor(
    Object? value,
    String label,
    String accountId, {
    bool allowNegative = false,
  }) {
    if (value is! int ||
        value.abs() > maxSafeMinorUnits ||
        (!allowNegative && value < 0)) {
      throw FormatException(
        'Invalid $label minor units for account $accountId.',
      );
    }
    return value;
  }
}
