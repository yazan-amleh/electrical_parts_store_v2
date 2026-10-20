class BookingCustomer {
  BookingCustomer({
    required this.id,
    required this.storeId,
    required this.name,
    required this.phoneNumber,
    this.email,
    this.address,
    this.notes,
    required this.createdAt,
    this.updatedAt,
  }) {
    _ensureIdentifier(id, 'Booking customer id');
    _ensureIdentifier(storeId, 'Store id');
    if (name.trim().isEmpty || phoneNumber.trim().isEmpty) {
      throw ArgumentError('Booking customer name and phone are required.');
    }
  }

  final String id;
  final String storeId;
  final String name;
  final String phoneNumber;
  final String? email;
  final String? address;
  final String? notes;
  final DateTime createdAt;
  final DateTime? updatedAt;

  BookingCustomer copyWith({
    String? name,
    String? phoneNumber,
    String? email,
    String? address,
    String? notes,
    DateTime? updatedAt,
  }) {
    return BookingCustomer(
      id: id,
      storeId: storeId,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static void _ensureIdentifier(String value, String label) {
    if (value.trim().isEmpty || value.contains('/')) {
      throw ArgumentError('$label is invalid.');
    }
  }
}
