import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../../infrastructure/firebase/firebase_paths.dart';
import '../../domain/entities/category.dart';
import '../../domain/repositories/category_repository.dart';
import '../mappers/category_firestore_mapper.dart';

class FirestoreCategoryRepository implements CategoryRepository {
  FirestoreCategoryRepository({required FirebaseFirestore firestore})
    : _firestore = firestore;

  final FirebaseFirestore _firestore;

  @override
  Future<Result<List<Category>>> getCategories({
    required StoreContext context,
    bool includeInactive = false,
  }) async {
    try {
      Query<Map<String, dynamic>> query = FirebasePaths.categories(
        _firestore,
        context.storeId,
      );
      if (!includeInactive) {
        query = query.where('isActive', isEqualTo: true);
      }

      final snapshot = await query.get();
      final categories =
          snapshot.docs
              .map(CategoryFirestoreMapper.fromSnapshot)
              .where((category) => category.storeId == context.storeId)
              .toList()
            ..sort((left, right) {
              final order = left.sortOrder.compareTo(right.sortOrder);
              return order == 0 ? left.name.compareTo(right.name) : order;
            });
      return Success<List<Category>>(categories);
    } on FirebaseException catch (error) {
      return FailureResult<List<Category>>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<List<Category>>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<void>> saveCategory({
    required StoreContext context,
    required Category category,
  }) async {
    if (category.storeId != context.storeId) {
      return const FailureResult<void>(
        AuthorizationFailure('Category does not belong to the active store.'),
      );
    }
    if (category.id.trim().isEmpty || category.id.contains('/')) {
      return const FailureResult<void>(
        ValidationFailure('Category id is invalid.'),
      );
    }
    if (category.name.trim().isEmpty) {
      return const FailureResult<void>(
        ValidationFailure('Category name is required.'),
      );
    }
    if (category.parentId == category.id) {
      return const FailureResult<void>(
        ValidationFailure('A category cannot be its own parent.'),
      );
    }

    try {
      return await _firestore.runTransaction<Result<void>>((transaction) async {
        final categoryReference = FirebasePaths.categories(
          _firestore,
          context.storeId,
        ).doc(category.id);
        final existingSnapshot = await transaction.get(categoryReference);
        if (existingSnapshot.exists) {
          final existing = CategoryFirestoreMapper.fromSnapshot(
            existingSnapshot,
          );
          if (existing.storeId != context.storeId) {
            return const FailureResult<void>(
              AuthorizationFailure('Category belongs to another store.'),
            );
          }
        }

        if (category.parentId != null) {
          final parentReference = FirebasePaths.categories(
            _firestore,
            context.storeId,
          ).doc(category.parentId);
          final parentSnapshot = await transaction.get(parentReference);
          if (!parentSnapshot.exists) {
            return const FailureResult<void>(
              ValidationFailure('Parent category was not found.'),
            );
          }
        }

        transaction.set(
          categoryReference,
          CategoryFirestoreMapper.toMap(category),
        );
        return const Success<void>(null);
      });
    } on FirebaseException catch (error) {
      return FailureResult<void>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<void>(InfrastructureFailure(error.toString()));
    }
  }
}
