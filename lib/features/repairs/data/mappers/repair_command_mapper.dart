import '../../domain/entities/repair_payment.dart';
import '../../domain/entities/repair_request.dart';
import '../../domain/entities/repair_posting_accounts.dart';
import '../../../payments/domain/enums/party_payment_method.dart';

abstract final class RepairCommandMapper {
  static Map<String, dynamic> createRequest(RepairRequest repair) {
    return <String, dynamic>{
      'storeId': repair.storeId,
      'repair': _repairPayload(repair),
    };
  }

  static Map<String, dynamic> updateRequest(RepairRequest repair) {
    return <String, dynamic>{
      'storeId': repair.storeId,
      'repairId': repair.id,
      'repair': _repairPayload(repair),
    };
  }

  static Map<String, dynamic> deliverRequest({
    required String storeId,
    required String repairId,
    required String idempotencyKey,
    required DateTime postedAt,
    required RepairPostingAccounts accounts,
  }) {
    return <String, dynamic>{
      'storeId': storeId,
      'repairId': repairId,
      'idempotencyKey': idempotencyKey,
      'postedAt': postedAt.toUtc().toIso8601String(),
      'accounts': <String, dynamic>{
        'customerReceivableAccountId': accounts.customerReceivableAccountId,
        'repairRevenueAccountId': accounts.repairRevenueAccountId,
        'inventoryAccountId': accounts.inventoryAccountId,
        'costOfSalesAccountId': accounts.costOfSalesAccountId,
        'customerAdvancesAccountId': accounts.customerAdvancesAccountId,
      },
    };
  }

  static Map<String, dynamic> paymentRequest({
    required RepairPayment payment,
    required RepairPostingAccounts accounts,
  }) {
    return <String, dynamic>{
      'storeId': payment.storeId,
      'repairId': payment.repairId,
      'payment': <String, dynamic>{
        'id': payment.id,
        'idempotencyKey': payment.idempotencyKey.value,
        'postedAt': payment.postedAt.toUtc().toIso8601String(),
        'paymentMethod': payment.paymentMethod.name,
        'amountMinorUnits': payment.amount.minorUnits,
        'currency': payment.amount.currency,
        'description': payment.description,
        'chequeNumber': payment.chequeNumber,
        'bankName': payment.bankName,
        'dueDate': payment.dueDate?.toUtc().toIso8601String(),
      },
      'postingAccounts': <String, dynamic>{
        'settlementAccountId': _settlementAccountId(
          payment.paymentMethod,
          accounts,
        ),
        'customerReceivableAccountId': accounts.customerReceivableAccountId,
        'customerAdvancesAccountId': accounts.customerAdvancesAccountId,
      },
    };
  }

  static Map<String, dynamic> _repairPayload(RepairRequest repair) {
    return <String, dynamic>{
      'id': repair.id,
      'idempotencyKey': repair.idempotencyKey.value,
      'customerId': repair.customerId,
      'deviceName': repair.deviceName,
      'deviceModel': repair.deviceModel,
      'problemDescription': repair.problemDescription,
      'createdAt': repair.createdAt.toUtc().toIso8601String(),
      'receivedAt': repair.receivedAt.toUtc().toIso8601String(),
      'expectedDeliveryDate':
          repair.expectedDeliveryDate.toUtc().toIso8601String(),
      'status': repair.status.name,
      'estimatedCostMinorUnits': repair.estimatedCost.minorUnits,
      'laborCostMinorUnits': repair.laborCost.minorUnits,
      'currency': repair.laborCost.currency,
      'technicianNotes': repair.technicianNotes,
      'serialNumber': repair.serialNumber,
      'priority': repair.priority.name,
      'deviceCondition': repair.deviceCondition.name,
      'deviceConditionNotes': repair.deviceConditionNotes,
      'requiredParts': repair.requiredParts,
      'requiredPartsStatus': repair.requiredPartsStatus,
      'deviceImages': repair.deviceImages,
      'parts': [
        for (final part in repair.parts)
          <String, dynamic>{
            'id': part.id,
            'productId': part.productId,
            'productName': part.productName,
            'quantityMilliUnits': part.quantity.milliUnits,
            'unitPriceMinorUnits': part.unitPrice.minorUnits,
            'unitCostMinorUnits': part.unitCost.minorUnits,
            'currency': part.unitPrice.currency,
            'source': part.source,
          },
      ],
    };
  }

  static String _settlementAccountId(
    PartyPaymentMethod paymentMethod,
    RepairPostingAccounts accounts,
  ) {
    switch (paymentMethod) {
      case PartyPaymentMethod.bank:
        return accounts.bankAccountId;
      case PartyPaymentMethod.card:
        return accounts.cardReceivableAccountId;
      case PartyPaymentMethod.cheque:
        return accounts.checksAccountId;
      case PartyPaymentMethod.cash:
        return accounts.settlementAccountId;
    }
  }
}
