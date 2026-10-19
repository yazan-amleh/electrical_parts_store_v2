class Category {
  const Category({
    required this.id,
    required this.storeId,
    required this.name,
    this.parentId,
    this.sortOrder = 0,
    this.isActive = true,
  });

  final String id;
  final String storeId;
  final String name;
  final String? parentId;
  final int sortOrder;
  final bool isActive;

  bool get isRoot => parentId == null;

  Category copyWith({
    String? name,
    String? parentId,
    bool clearParent = false,
    int? sortOrder,
    bool? isActive,
  }) {
    return Category(
      id: id,
      storeId: storeId,
      name: name ?? this.name,
      parentId: clearParent ? null : parentId ?? this.parentId,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
    );
  }
}
