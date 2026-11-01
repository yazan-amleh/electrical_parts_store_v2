import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../../infrastructure/firebase/firebase_paths.dart';
import '../../domain/entities/voucher_record.dart';
import '../../domain/repositories/voucher_query_repository.dart';
import '../mappers/voucher_firestore_mapper.dart';

class FirestoreVoucherQueryRepository implements VoucherQueryRepository {
  const FirestoreVoucherQueryRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  @override
  Future<Result<VoucherPage>> getVoucherPage({
    required StoreContext context,
    VoucherCursor? after,
    int pageSize = 50,
  }) async {
    if (context.storeId.trim().isEmpty ||
        context.userId.trim().isEmpty ||
        pageSize < 1 ||
        pageSize > 100) {
      return const FailureResult<VoucherPage>(
        ValidationFailure('Invalid voucher query parameters.'),
      );
    }
    try {
      Query<Map<String, dynamic>> query = FirebasePaths.partyPayments(
        _firestore,
        context.storeId,
      )
          .orderBy('postedAt', descending: true)
          .orderBy(FieldPath.documentId, descending: true)
          .limit(pageSize + 1);
      if (after != null) {
        query = query.startAfter([
          Timestamp.fromDate(after.postedAt.toUtc()),
          after.id,
        ]);
      }
      final snapshot = await query.get();
      final hasMore = snapshot.docs.length > pageSize;
      final documents = snapshot.docs.take(pageSize);
      final records = <VoucherRecord>[];
      for (final document in documents) {
        records.add(
          VoucherFirestoreMapper.fromMap(
            documentId: document.id,
            expectedStoreId: context.storeId,
            data: document.data(),
          ),
        );
      }
      final last = records.isEmpty ? null : records.last;
      return Success<VoucherPage>(
        VoucherPage(
          records: records,
          hasMore: hasMore,
          nextCursor: hasMore && last != null
              ? VoucherCursor(id: last.id, postedAt: last.postedAt)
              : null,
        ),
      );
    } on FirebaseException catch (error) {
      return FailureResult<VoucherPage>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } on FormatException catch (error) {
      return FailureResult<VoucherPage>(
        ValidationFailure(error.message),
      );
    } catch (error) {
      return FailureResult<VoucherPage>(
        InfrastructureFailure(error.toString()),
      );
    }
  }
}
