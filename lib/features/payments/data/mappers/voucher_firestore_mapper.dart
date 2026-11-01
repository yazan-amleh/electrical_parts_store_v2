import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/money/money.dart';
import '../../../parties/domain/enums/party_type.dart';
import '../../domain/entities/voucher_record.dart';
import '../../domain/enums/party_payment_method.dart';

abstract final class VoucherFirestoreMapper {
  static VoucherRecord fromMap({
    required String documentId,
    required String expectedStoreId,
    required Map<String, dynamic> data,
  }) {
    if (documentId.trim().isEmpty ||
        documentId.contains('/') ||
        data['storeId'] != expectedStoreId ||
        data['journalEntryId'] is! String ||
        (data['journalEntryId'] as String).trim().isEmpty) {
      throw const FormatException(
          'Voucher ownership or journal link is invalid.');
    }
    final partyType = switch (data['partyType']) {
      'customer' => PartyType.customer,
      'supplier' => PartyType.supplier,
      _ => throw const FormatException('Unrecognized voucher direction.'),
    };
    final method = switch (data['paymentMethod']) {
      'cash' => PartyPaymentMethod.cash,
      'bank' => PartyPaymentMethod.bank,
      'card' => PartyPaymentMethod.card,
      'cheque' => PartyPaymentMethod.cheque,
      _ => throw const FormatException('Unrecognized voucher method.'),
    };
    final amount = data['amountMinorUnits'];
    final currency = data['currency'];
    final posted = data['postedAt'];
    final partyId = data['partyId'];
    final status = data['status'];
    if (amount is! int ||
        amount <= 0 ||
        currency is! String ||
        currency.trim().isEmpty ||
        partyId is! String ||
        partyId.trim().isEmpty ||
        posted is! Timestamp ||
        status is! String ||
        !const {'posted', 'pending', 'cleared', 'bounced'}.contains(status)) {
      throw const FormatException('Voucher has incomplete financial fields.');
    }
    return VoucherRecord(
      id: documentId,
      storeId: expectedStoreId,
      partyType: partyType,
      partyId: partyId,
      paymentMethod: method,
      amount: Money(minorUnits: amount, currency: currency),
      postedAt: posted.toDate().toUtc(),
      journalEntryId: data['journalEntryId'] as String,
      status: status,
      description: data['description'] as String?,
      voucherNumber: data['voucherNumber'] as String?,
      repairId: data['repairId'] as String?,
      paymentKind: data['paymentKind'] as String?,
    );
  }
}
