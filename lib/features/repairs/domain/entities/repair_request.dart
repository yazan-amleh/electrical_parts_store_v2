import '../../../../core/idempotency/idempotency_key.dart';
import '../../../../core/money/money.dart';
import '../../../../core/tenancy/store_context.dart';
import '../enums/device_condition.dart';
import '../enums/repair_priority.dart';
import '../enums/repair_status.dart';
import 'repair_part.dart';

class RepairRequest {
  RepairRequest({
    required this.id,
    required this.storeId,
    required this.idempotencyKey,
    required this.customerId,
    required this.deviceName,
    required this.deviceModel,
    required this.problemDescription,
    required DateTime createdAt,
    required DateTime receivedAt,
    required DateTime expectedDeliveryDate,
    this.status = RepairStatus.received,
    Money? estimatedCost,
    Money? laborCost,
    List<RepairPart> parts = const [],
    this.technicianNotes = '',
    this.serialNumber = '',
    this.priority = RepairPriority.normal,
    this.deviceCondition = DeviceCondition.notWorking,
    this.deviceConditionNotes = '',
    List<String> requiredParts = const [],
    Map<String, String> requiredPartsStatus = const {},
    List<String> deviceImages = const [],
    DateTime? completedAt,
    DateTime? actualDeliveryDate,
    Money? advancePaid,
    Money? paid,
    this.invoiceJournalEntryId,
    Money? invoicedTotal,
    Money? costOfParts,
  })  : createdAt = createdAt.toUtc(),
        receivedAt = receivedAt.toUtc(),
        expectedDeliveryDate = expectedDeliveryDate.toUtc(),
        completedAt = completedAt?.toUtc(),
        actualDeliveryDate = actualDeliveryDate?.toUtc(),
        estimatedCost = estimatedCost ?? Money.zero(),
        laborCost = laborCost ?? Money.zero(),
        parts = List.unmodifiable(parts),
        requiredParts = List.unmodifiable(requiredParts),
        requiredPartsStatus = Map.unmodifiable(requiredPartsStatus),
        deviceImages = List.unmodifiable(deviceImages),
        advancePaid = advancePaid ?? Money.zero(),
        paid = paid ?? Money.zero(),
        invoicedTotal = invoicedTotal ?? Money.zero(),
        costOfParts = costOfParts ?? Money.zero() {
    _ensureIdentifier(id, 'Repair id');
    _ensureIdentifier(storeId, 'Repair store id');
    _ensureIdentifier(customerId, 'Repair customer id');
    if (idempotencyKey.value.contains('/')) {
      throw ArgumentError('Repair idempotency key cannot contain a slash.');
    }
    if (deviceName.trim().isEmpty) {
      throw ArgumentError('Repair device name is required.');
    }
    if (deviceModel.trim().isEmpty) {
      throw ArgumentError('Repair device model is required.');
    }
    if (estimatedCost.isNegative ||
        laborCost.isNegative ||
        advancePaid.isNegative ||
        paid.isNegative ||
        invoicedTotal.isNegative ||
        costOfParts.isNegative) {
      throw ArgumentError('Repair amounts cannot be negative.');
    }

    final currency = this.laborCost.currency;
    for (final amount in [
      this.estimatedCost,
      this.advancePaid,
      this.paid,
      this.invoicedTotal,
      this.costOfParts,
    ]) {
      if (amount.currency != currency) {
        throw ArgumentError('Repair amounts must use one currency.');
      }
    }
    for (final part in this.parts) {
      if (part.unitPrice.currency != currency ||
          part.unitCost.currency != currency) {
        throw ArgumentError('Repair part currency does not match repair.');
      }
    }
  }

  final String id;
  final String storeId;
  final IdempotencyKey idempotencyKey;
  final String customerId;
  final String deviceName;
  final String deviceModel;
  final String problemDescription;
  final DateTime createdAt;
  final DateTime receivedAt;
  final DateTime expectedDeliveryDate;
  final RepairStatus status;
  final Money estimatedCost;
  final Money laborCost;
  final List<RepairPart> parts;
  final String technicianNotes;
  final String serialNumber;
  final RepairPriority priority;
  final DeviceCondition deviceCondition;
  final String deviceConditionNotes;
  final List<String> requiredParts;
  final Map<String, String> requiredPartsStatus;
  final List<String> deviceImages;
  final DateTime? completedAt;
  final DateTime? actualDeliveryDate;
  final Money advancePaid;
  final Money paid;
  final String? invoiceJournalEntryId;
  final Money invoicedTotal;
  final Money costOfParts;

  Money get partsTotal {
    return parts.fold(
      Money.zero(currency: laborCost.currency),
      (total, part) => total + part.totalPrice,
    );
  }

  Money get finalCost => laborCost + partsTotal;

  Money get outstanding {
    final total = invoicedTotal.isZero ? finalCost : invoicedTotal;
    final remaining = total.minorUnits - paid.minorUnits;
    return Money(
      minorUnits: remaining < 0 ? 0 : remaining,
      currency: total.currency,
    );
  }

  bool get isInvoiced => invoiceJournalEntryId != null;
  bool get isPaid => !invoicedTotal.isZero && paid.minorUnits >= invoicedTotal.minorUnits;

  RepairRequest copyWith({
    String? id,
    String? storeId,
    IdempotencyKey? idempotencyKey,
    String? customerId,
    String? deviceName,
    String? deviceModel,
    String? problemDescription,
    DateTime? createdAt,
    DateTime? receivedAt,
    DateTime? expectedDeliveryDate,
    RepairStatus? status,
    Money? estimatedCost,
    Money? laborCost,
    List<RepairPart>? parts,
    String? technicianNotes,
    String? serialNumber,
    RepairPriority? priority,
    DeviceCondition? deviceCondition,
    String? deviceConditionNotes,
    List<String>? requiredParts,
    Map<String, String>? requiredPartsStatus,
    List<String>? deviceImages,
    DateTime? completedAt,
    DateTime? actualDeliveryDate,
    Money? advancePaid,
    Money? paid,
    String? invoiceJournalEntryId,
    Money? invoicedTotal,
    Money? costOfParts,
  }) {
    return RepairRequest(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      customerId: customerId ?? this.customerId,
      deviceName: deviceName ?? this.deviceName,
      deviceModel: deviceModel ?? this.deviceModel,
      problemDescription: problemDescription ?? this.problemDescription,
      createdAt: createdAt ?? this.createdAt,
      receivedAt: receivedAt ?? this.receivedAt,
      expectedDeliveryDate:
          expectedDeliveryDate ?? this.expectedDeliveryDate,
      status: status ?? this.status,
      estimatedCost: estimatedCost ?? this.estimatedCost,
      laborCost: laborCost ?? this.laborCost,
      parts: parts ?? this.parts,
      technicianNotes: technicianNotes ?? this.technicianNotes,
      serialNumber: serialNumber ?? this.serialNumber,
      priority: priority ?? this.priority,
      deviceCondition: deviceCondition ?? this.deviceCondition,
      deviceConditionNotes:
          deviceConditionNotes ?? this.deviceConditionNotes,
      requiredParts: requiredParts ?? this.requiredParts,
      requiredPartsStatus:
          requiredPartsStatus ?? this.requiredPartsStatus,
      deviceImages: deviceImages ?? this.deviceImages,
      completedAt: completedAt ?? this.completedAt,
      actualDeliveryDate: actualDeliveryDate ?? this.actualDeliveryDate,
      advancePaid: advancePaid ?? this.advancePaid,
      paid: paid ?? this.paid,
      invoiceJournalEntryId:
          invoiceJournalEntryId ?? this.invoiceJournalEntryId,
      invoicedTotal: invoicedTotal ?? this.invoicedTotal,
      costOfParts: costOfParts ?? this.costOfParts,
    );
  }
}
