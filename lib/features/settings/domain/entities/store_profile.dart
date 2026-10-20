class StoreProfile {
  StoreProfile({
    required this.id,
    required this.name,
    required this.currency,
    this.phone = '',
    this.address = '',
  }) {
    if (id.trim().isEmpty || name.trim().isEmpty) {
      throw ArgumentError('Store id and name are required.');
    }
    if (currency.trim().isEmpty || currency.contains('/')) {
      throw ArgumentError('Store currency is invalid.');
    }
  }

  final String id;
  final String name;
  final String currency;
  final String phone;
  final String address;
}
