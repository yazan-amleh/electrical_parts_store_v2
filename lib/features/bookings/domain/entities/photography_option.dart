import '../../../../core/money/money.dart';

class PhotographyOption {
  PhotographyOption({
    required this.id,
    required this.storeId,
    required this.name,
    required this.description,
    required this.price,
    required this.durationMinutes,
    required this.isActive,
    required this.createdAt,
    this.updatedAt,
  }) {
    _ensureIdentifier(id, 'Photography option id');
    _ensureIdentifier(storeId, 'Store id');
    if (name.trim().isEmpty) {
      throw ArgumentError('Photography option name is required.');
    }
    if (price.isNegative || durationMinutes < 0) {
      throw ArgumentError('Photography option price or duration is invalid.');
    }
  }

  final String id;
  final String storeId;
  final String name;
  final String description;
  final Money price;
  final int durationMinutes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? updatedAt;

  PhotographyOption copyWith({
    String? name,
    String? description,
    Money? price,
    int? durationMinutes,
    bool? isActive,
    DateTime? updatedAt,
  }) {
    return PhotographyOption(
      id: id,
      storeId: storeId,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      isActive: isActive ?? this.isActive,
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
