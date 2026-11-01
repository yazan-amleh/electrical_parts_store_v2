import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:electrical_parts_store_v2/features/payments/data/mappers/voucher_firestore_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 26, 13, 15);
  Map<String, dynamic> valid({
    String partyType = 'customer',
    String status = 'posted',
  }) {
    return {
      'storeId': 'store-a',
      'journalEntryId': 'payment-1-journal',
      'postedAt': Timestamp.fromDate(now),
      'partyType': partyType,
      'partyId': 'customer-1',
      'paymentMethod': 'cash',
      'amountMinorUnits': 12345,
      'currency': 'ILS',
      'status': status,
      'description': 'Payment received',
    };
  }

  test('maps transactional receipt with its true journal reference', () {
    final voucher = VoucherFirestoreMapper.fromMap(
      documentId: 'payment-1',
      expectedStoreId: 'store-a',
      data: valid(),
    );
    expect(voucher.id, 'payment-1');
    expect(voucher.isReceipt, isTrue);
    expect(voucher.journalEntryId, 'payment-1-journal');
    expect(voucher.amount.minorUnits, 12345);
    expect(voucher.statusLabel, 'مرحّل');
  });

  test('cheque pending is not treated as draft', () {
    final voucher = VoucherFirestoreMapper.fromMap(
      documentId: 'cheque-1',
      expectedStoreId: 'store-a',
      data: valid(status: 'pending'),
    );
    expect(voucher.statusLabel, 'شيك قيد التحصيل');
  });

  test('repair advance retains distinct payment classification', () {
    final fields = valid();
    fields['repairId'] = 'repair-1';
    fields['paymentKind'] = 'advance';
    final voucher = VoucherFirestoreMapper.fromMap(
      documentId: 'advance-1',
      expectedStoreId: 'store-a',
      data: fields,
    );
    expect(voucher.typeLabel, 'دفعة مقدمة صيانة');
  });

  test('rejects wrong store and missing journal links', () {
    expect(
      () => VoucherFirestoreMapper.fromMap(
        documentId: 'payment-1',
        expectedStoreId: 'store-b',
        data: valid(),
      ),
      throwsFormatException,
    );
    final noJournal = valid()..remove('journalEntryId');
    expect(
      () => VoucherFirestoreMapper.fromMap(
        documentId: 'payment-1',
        expectedStoreId: 'store-a',
        data: noJournal,
      ),
      throwsFormatException,
    );
  });

  test('rejects negative or missing monetary fields', () {
    for (final value in [-1, 0, null]) {
      final record = valid()..['amountMinorUnits'] = value;
      expect(
        () => VoucherFirestoreMapper.fromMap(
          documentId: 'payment-1',
          expectedStoreId: 'store-a',
          data: record,
        ),
        throwsFormatException,
      );
    }
  });
}
