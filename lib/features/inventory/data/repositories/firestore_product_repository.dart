import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../../infrastructure/firebase/firebase_paths.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/product_repository.dart';
import '../mappers/product_firestore_mapper.dart';

class FirestoreProductRepository implements ProductRepository {
  FirestoreProductRepository({
    required FirebaseFirestore firestore,
  }) : _firestore = firestore;

  final FirebaseFirestore _firestore;

  @override
  Future<Result<List<Product>>> getProducts({
    required StoreContext context,
    bool includeInactive = false,
  }) async {
    try {
      Query<Map<String, dynamic>> query = FirebasePaths.products(
        _firestore,
        context.storeId,
      );
      if (!includeInactive) {
        query = query.where('isActive', isEqualTo: true);
      }

      final snapshot = await query.get();
      final products = snapshot.docs
          .map(ProductFirestoreMapper.fromSnapshot)
          .where((product) => product.storeId == context.storeId)
          .toList();
      return Success<List<Product>>(products);
    } on FirebaseException catch (error) {
      return FailureResult<List<Product>>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<List<Product>>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<Product>> getProduct({
    required StoreContext context,
    required String productId,
  }) async {
    try {
      final snapshot = await FirebasePaths.products(
        _firestore,
        context.storeId,
      ).doc(productId).get();

      if (!snapshot.exists) {
        return const FailureResult<Product>(
          ValidationFailure('Product was not found.'),
        );
      }

      final product = ProductFirestoreMapper.fromSnapshot(snapshot);
      if (product.storeId != context.storeId) {
        return const FailureResult<Product>(
          AuthorizationFailure('Product belongs to another store.'),
        );
      }

      return Success<Product>(product);
    } on FirebaseException catch (error) {
      return FailureResult<Product>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<Product>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<void>> saveProduct({
    required StoreContext context,
    required Product product,
  }) async {
    if (product.storeId != context.storeId) {
      return const FailureResult<void>(
        AuthorizationFailure('Product does not belong to the active store.'),
      );
    }

    try {
      await FirebasePaths.products(
        _firestore,
        context.storeId,
      ).doc(product.id).set(ProductFirestoreMapper.toMap(product));
      return const Success<void>(null);
    } on FirebaseException catch (error) {
      return FailureResult<void>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<void>(
        InfrastructureFailure(error.toString()),
      );
    }
  }
}
