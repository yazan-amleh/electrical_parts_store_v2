import '../../../../core/money/money.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/party_ledger_entry.dart';
import '../enums/party_type.dart';

abstract interface class PartyLedgerRepository {
  Future<Result<List<PartyLedgerEntry>>> getEntries({
    required StoreContext context,
    required PartyType partyType,
    required String partyId,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  });

  Future<Result<Money>> getBalance({
    required StoreContext context,
    required PartyType partyType,
    required String partyId,
    String currency = 'ILS',
  });
}
