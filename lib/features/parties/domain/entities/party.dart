import '../../../../core/money/money.dart';
import '../enums/party_type.dart';

class Party {
  Party({
    required this.id,
    required this.storeId,
    required this.type,
    required this.name,
    Money? creditLimit,
    this.phone,
    this.email,
    this.address,
    this.taxNumber,
    this.notes,
    this.isActive = true,
  }) : creditLimit = creditLimit ?? Money.zero() {
    if (id.trim().isEmpty || storeId.trim().isEmpty || name.trim().isEmpty) {
      throw ArgumentError('Party identity fields are required.');
    }
    if (id.contains('/') || storeId.contains('/')) {
      throw ArgumentError('Party identifiers cannot contain a slash.');
    }
    if (this.creditLimit.isNegative) {
      throw ArgumentError('Party credit limit cannot be negative.');
    }
  }

  final String id;
  final String storeId;
  final PartyType type;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? taxNumber;
  final String? notes;
  final Money creditLimit;
  final bool isActive;
}
