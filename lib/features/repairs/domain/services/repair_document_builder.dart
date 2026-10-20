import 'dart:typed_data';

import '../entities/repair_payment.dart';
import '../entities/repair_request.dart';

abstract interface class RepairDocumentBuilder {
  Future<Uint8List> buildRepairRequest({
    required RepairRequest repair,
    required String storeName,
    required String customerName,
    String? customerPhone,
  });

  Future<Uint8List> buildPaymentReceipt({
    required RepairPayment payment,
    required RepairRequest repair,
    required String storeName,
    required String customerName,
    String? customerPhone,
  });
}
