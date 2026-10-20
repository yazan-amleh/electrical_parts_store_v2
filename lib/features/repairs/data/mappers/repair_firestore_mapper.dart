import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/idempotency/idempotency_key.dart';
import '../../../../core/money/money.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../payments/domain/enums/party_payment_method.dart';
import '../../domain/entities/repair_part.dart';
import '../../domain/entities/repair_payment.dart';
import '../../domain/entities/repair_request.dart';
import '../../domain/enums/device_condition.dart';
import '../../domain/enums/repair_payment_kind.dart';
import '../../domain/enums/repair_priority.dart';
import '../../domain/enums/repair_status.dart';

abstract final class RepairFirestoreMapper {
  static RepairRequest requestFromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final id = snapshot.id;
    final currency = _string(data['currency'], 'ILS');
    final rawParts = data['parts'];
    final parts = rawParts is List
        ? rawParts
            .whereType<Map<Object?, Object?>>()
            .map(
              (raw) => RepairPart(
                id: _string(raw['id'], 'part-$id'),
                productId: _string(raw['productId']),
                productName: _string(raw['productName']),
                quantity: Quantity.fromMilliUnits(
                  _int(raw['quantityMilliUnits']),
                ),
                unitPrice: Money(
                  minorUnits: _int(raw['unitPriceMinorUnits']),
                  currency: _string(raw['currency'], currency),
                ),
                unitCost: Money(
                  minorUnits: _int(raw['unitCostMinorUnits']),
                  currency: _string(raw['currency'], currency),
                ),
                source: _string(raw['source'], 'products'),
              ),
            )
            .toList(growable: false)
        : const <RepairPart>[];

    final rawRequiredStatus = data['requiredPartsStatus'];
    final requiredPartsStatus = rawRequiredStatus is Map
        ? rawRequiredStatus.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          )
        : const <String, String>{};

    return RepairRequest(
      id: id,
      storeId: _string(data['storeId']),
      idempotencyKey: IdempotencyKey(
        _string(data['idempotencyKey'], id),
      ),
      customerId: _string(data['customerId']),
      deviceName: _string(data['deviceName']),
      deviceModel: _string(data['deviceModel']),
      problemDescription: _string(data['problemDescription']),
      createdAt: _date(data['createdAt']) ?? DateTime.now().toUtc(),
      receivedAt: _date(data['receivedAt']) ??
          _date(data['createdAt']) ??
          DateTime.now().toUtc(),
      expectedDeliveryDate:
          _date(data['expectedDeliveryDate']) ?? DateTime.now().toUtc(),
      status: _enumValue(
        RepairStatus.values,
        _string(data['status'], RepairStatus.received.name),
        RepairStatus.received,
      ),
      estimatedCost: _money(data, 'estimatedCostMinorUnits', currency),
      laborCost: _money(data, 'laborCostMinorUnits', currency),
      parts: parts,
      technicianNotes: _string(data['technicianNotes']),
      serialNumber: _string(data['serialNumber']),
      priority: _enumValue(
        RepairPriority.values,
        _string(data['priority'], RepairPriority.normal.name),
        RepairPriority.normal,
      ),
      deviceCondition: _enumValue(
        DeviceCondition.values,
        _string(data['deviceCondition'], DeviceCondition.notWorking.name),
        DeviceCondition.notWorking,
      ),
      deviceConditionNotes: _string(data['deviceConditionNotes']),
      requiredParts: _strings(data['requiredParts']),
      requiredPartsStatus: requiredPartsStatus,
      deviceImages: _strings(data['deviceImages']),
      completedAt: _date(data['completedAt']),
      actualDeliveryDate: _date(data['actualDeliveryDate']),
      advancePaid: _money(data, 'advancePaidMinorUnits', currency),
      paid: _money(data, 'paidMinorUnits', currency),
      invoiceJournalEntryId: data['invoiceJournalEntryId'] as String?,
      invoicedTotal: _money(data, 'invoicedTotalMinorUnits', currency),
      costOfParts: _money(data, 'costOfPartsMinorUnits', currency),
    );
  }

  static RepairPayment paymentFromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final currency = _string(data['currency'], 'ILS');
    return RepairPayment(
      id: snapshot.id,
      storeId: _string(data['storeId']),
      repairId: _string(data['repairId']),
      customerId: _string(data['customerId']),
      idempotencyKey: IdempotencyKey(
        _string(data['idempotencyKey'], snapshot.id),
      ),
      postedAt: _date(data['postedAt']) ?? DateTime.now().toUtc(),
      kind: _enumValue(
        RepairPaymentKind.values,
        _string(data['paymentKind'], RepairPaymentKind.settlement.name),
        RepairPaymentKind.settlement,
      ),
      paymentMethod: _enumValue(
        PartyPaymentMethod.values,
        _string(data['paymentMethod'], PartyPaymentMethod.cash.name),
        PartyPaymentMethod.cash,
      ),
      amount: Money(
        minorUnits: _int(data['amountMinorUnits']),
        currency: currency,
      ),
      description: data['description'] as String?,
      chequeNumber: data['chequeNumber'] as String?,
      bankName: data['bankName'] as String?,
      dueDate: _date(data['dueDate']),
    );
  }

  static Money _money(
    Map<String, dynamic> data,
    String key,
    String currency,
  ) {
    return Money(
      minorUnits: _int(data[key]),
      currency: currency,
    );
  }

  static List<String> _strings(Object? value) {
    if (value is! List) {
      return const [];
    }
    return value.whereType<String>().toList(growable: false);
  }

  static DateTime? _date(Object? value) {
    if (value is Timestamp) {
      return value.toDate().toUtc();
    }
    if (value is DateTime) {
      return value.toUtc();
    }
    if (value is String) {
      return DateTime.tryParse(value)?.toUtc();
    }
    return null;
  }

  static String _string(Object? value, [String fallback = '']) {
    return value is String && value.trim().isNotEmpty ? value.trim() : fallback;
  }

  static int _int(Object? value) {
    return value is int
        ? value
        : value is num
            ? value.toInt()
            : 0;
  }

  static T _enumValue<T extends Enum>(
    List<T> values,
    String name,
    T fallback,
  ) {
    return values.firstWhere(
      (candidate) => candidate.name == name,
      orElse: () => fallback,
    );
  }
}
