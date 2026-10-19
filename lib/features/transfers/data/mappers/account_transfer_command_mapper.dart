import '../../domain/entities/account_transfer.dart';

abstract final class AccountTransferCommandMapper {
  static Map<String, dynamic> toRequest({
    required AccountTransfer transfer,
  }) {
    return <String, dynamic>{
      'storeId': transfer.storeId,
      'transfer': <String, dynamic>{
        'id': transfer.id,
        'idempotencyKey': transfer.idempotencyKey.value,
        'postedAt': transfer.postedAt.toUtc().toIso8601String(),
        'fromAccountId': transfer.fromAccountId,
        'toAccountId': transfer.toAccountId,
        'amountMinorUnits': transfer.amount.minorUnits,
        'currency': transfer.amount.currency,
        'description': transfer.description,
      },
    };
  }
}
