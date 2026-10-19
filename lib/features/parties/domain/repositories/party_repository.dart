import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/party.dart';
import '../entities/party_balance.dart';
import '../enums/party_type.dart';

abstract interface class PartyRepository {
  Future<Result<List<Party>>> getParties({
    required StoreContext context,
    required PartyType type,
    bool includeInactive = false,
  });

  Future<Result<Party>> getParty({
    required StoreContext context,
    required String partyId,
  });

  Future<Result<void>> saveParty({
    required StoreContext context,
    required Party party,
  });

  Future<Result<Map<String, PartyBalance>>> getBalances({
    required StoreContext context,
    required PartyType type,
  });
}
