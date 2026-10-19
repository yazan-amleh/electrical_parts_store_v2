import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/category.dart';

abstract final class CategoryFirestoreMapper {
  static Category fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return Category(
      id: snapshot.id,
      storeId: _string(data['storeId']),
      name: _string(data['name'], snapshot.id),
      parentId: data['parentId'] as String?,
      sortOrder: _int(data['sortOrder']),
      isActive: data['isActive'] is bool ? data['isActive'] as bool : true,
    );
  }

  static Map<String, dynamic> toMap(Category category) {
    return <String, dynamic>{
      'storeId': category.storeId,
      'name': category.name,
      'parentId': category.parentId,
      'sortOrder': category.sortOrder,
      'isActive': category.isActive,
    };
  }

  static String _string(Object? value, [String fallback = '']) {
    return value is String && value.trim().isNotEmpty ? value : fallback;
  }

  static int _int(Object? value) {
    return value is int
        ? value
        : value is num
            ? value.toInt()
            : 0;
  }
}
