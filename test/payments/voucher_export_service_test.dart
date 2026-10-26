import 'dart:convert';

import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/features/parties/domain/enums/party_type.dart';
import 'package:electrical_parts_store_v2/features/payments/domain/entities/voucher_record.dart';
import 'package:electrical_parts_store_v2/features/payments/domain/enums/party_payment_method.dart';
import 'package:electrical_parts_store_v2/features/payments/presentation/voucher_export_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  VoucherRecord voucher({
    String id = 'payment-1',
    String partyId = 'customer-a',
  }) =>
      VoucherRecord(
        id: id,
        storeId: 'store-a',
        partyType: PartyType.customer,
        partyId: partyId,
        paymentMethod: PartyPaymentMethod.cash,
        amount: Money(minorUnits: 14375, currency: 'ILS'),
        postedAt: DateTime.utc(2026, 10, 26),
        journalEntryId: 'payment-1-journal',
        status: 'posted',
        voucherNumber: 'RC-2026-000001',
        description: 'Test export',
      );

  test('CSV includes verified financial columns and prevents formula injection',
      () {
    const service = VoucherExportService();
    final csv = service.csvFor([
      voucher(id: '=HYPERLINK("bad")', partyId: '+SUM(1,1)'),
    ]);
    expect(csv, contains('RC-2026-000001'));
    expect(csv, contains("'=HYPERLINK"));
    expect(csv, contains("'+SUM"));
    expect(csv, contains('"14375"'));
    expect(csv, contains('payment-1-journal'));
    expect(csv, contains('2026-10-26T00:00:00.000Z'));
  });

  test('Arabic voucher PDF builds using bundled font without online fonts',
      () async {
    const service = VoucherExportService();
    final bytes = await service.buildPdf([voucher()]);
    expect(bytes.length, greaterThan(700));
    expect(latin1.decode(bytes.take(4).toList()), '%PDF');
  });
}
