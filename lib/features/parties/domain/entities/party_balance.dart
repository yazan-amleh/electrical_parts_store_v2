import '../../../../core/money/money.dart';
import '../enums/party_type.dart';

class PartyBalance {
  const PartyBalance({
    required this.partyType,
    required this.partyId,
    required this.debit,
    required this.credit,
    required this.balance,
  });

  final PartyType partyType;
  final String partyId;
  final Money debit;
  final Money credit;
  final Money balance;
}
