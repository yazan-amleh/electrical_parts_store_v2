import 'package:electrical_parts_store_v2/features/accounting/data/mappers/account_balance_firestore_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> good() => {
        'storeId': 'v2-store-a',
        'accountId': '1110',
        'currency': 'ILS',
        'debitMinorUnits': 17500,
        'creditMinorUnits': 2500,
        'balanceMinorUnits': 15000,
      };

  test('reads exact integer balances and reconciles net amount', () {
    final result = AccountBalanceFirestoreMapper.fromMap(
      data: good(),
      documentAccountId: '1110',
      expectedStoreId: 'v2-store-a',
    );
    expect(result.accountId, '1110');
    expect(result.debit.minorUnits, 17500);
    expect(result.credit.minorUnits, 2500);
    expect(result.debitCreditBalance.minorUnits, 15000);
    expect(result.debit.currency, 'ILS');
  });

  test('rejects a projection belonging to another tenant', () {
    final data = good()..['storeId'] = 'v2-store-b';
    expect(
      () => AccountBalanceFirestoreMapper.fromMap(
        data: data,
        documentAccountId: '1110',
        expectedStoreId: 'v2-store-a',
      ),
      throwsFormatException,
    );
  });

  test('rejects a projection whose account ID differs from document ID', () {
    final data = good()..['accountId'] = '1121';
    expect(
      () => AccountBalanceFirestoreMapper.fromMap(
        data: data,
        documentAccountId: '1110',
        expectedStoreId: 'v2-store-a',
      ),
      throwsFormatException,
    );
  });

  test('does not turn missing or fractional debit data into zero', () {
    for (final amount in <Object?>[null, 12.5, '0', -1]) {
      final data = good()..['debitMinorUnits'] = amount;
      expect(
        () => AccountBalanceFirestoreMapper.fromMap(
          data: data,
          documentAccountId: '1110',
          expectedStoreId: 'v2-store-a',
        ),
        throwsFormatException,
      );
    }
  });

  test('rejects non-reconciling net values and missing currency', () {
    for (final changed in <Map<String, dynamic>>[
      good()..['balanceMinorUnits'] = 123,
      good()..remove('currency'),
      good()..['currency'] = '',
    ]) {
      expect(
        () => AccountBalanceFirestoreMapper.fromMap(
          data: changed,
          documentAccountId: '1110',
          expectedStoreId: 'v2-store-a',
        ),
        throwsFormatException,
      );
    }
  });

  test('rejects amounts outside JavaScript safe integer range', () {
    final data = good()
      ..['debitMinorUnits'] =
          AccountBalanceFirestoreMapper.maxSafeMinorUnits + 1;
    expect(
      () => AccountBalanceFirestoreMapper.fromMap(
        data: data,
        documentAccountId: '1110',
        expectedStoreId: 'v2-store-a',
      ),
      throwsFormatException,
    );
  });
}
