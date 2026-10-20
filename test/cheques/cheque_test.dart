import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/features/cheques/domain/entities/cheque.dart';
import 'package:electrical_parts_store_v2/features/cheques/domain/enums/cheque_status.dart';
import 'package:electrical_parts_store_v2/features/parties/domain/enums/party_type.dart';

void main() {
  Cheque cheque({
    ChequeStatus status = ChequeStatus.pending,
    String? settlementJournalEntryId,
    PartyType partyType = PartyType.customer,
  }) {
    return Cheque(
      id: 'cheque-1',
      storeId: 'store-1',
      partyType: partyType,
      partyId: partyType == PartyType.customer ? 'customer-1' : 'supplier-1',
      amount: const Money(minorUnits: 12500),
      chequeNumber: 'CHK-1',
      bankName: 'Main Bank',
      receivedAt: DateTime.utc(2026, 1, 1),
      status: status,
      settlementJournalEntryId: settlementJournalEntryId,
    );
  }

  test('incoming cheque starts pending and uses exact minor units', () {
    final value = cheque();

    expect(value.status, ChequeStatus.pending);
    expect(value.amount, const Money(minorUnits: 12500));
    expect(value.partyType, PartyType.customer);
  });

  test('supports an outbound supplier cheque as a separate direction', () {
    final value = cheque(partyType: PartyType.supplier);

    expect(value.partyType, PartyType.supplier);
    expect(value.partyId, 'supplier-1');
  });

  test('settled cheque requires a settlement journal', () {
    expect(
      () => cheque(status: ChequeStatus.cleared),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      cheque(
        status: ChequeStatus.bounced,
        settlementJournalEntryId: 'journal-1',
      ).settlementJournalEntryId,
      'journal-1',
    );
  });

  test('cheque must have a number and bank', () {
    expect(
      () => Cheque(
        id: 'cheque-2',
        storeId: 'store-1',
        partyType: PartyType.customer,
        partyId: 'customer-1',
        amount: const Money(minorUnits: 100),
        chequeNumber: '',
        bankName: 'Main Bank',
        receivedAt: DateTime.utc(2026, 1, 1),
        status: ChequeStatus.pending,
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => Cheque(
        id: 'cheque-3',
        storeId: 'store-1',
        partyType: PartyType.customer,
        partyId: 'customer-1',
        amount: const Money(minorUnits: 100),
        chequeNumber: 'CHK-3',
        bankName: '',
        receivedAt: DateTime.utc(2026, 1, 1),
        status: ChequeStatus.pending,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
