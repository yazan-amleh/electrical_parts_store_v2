import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../../infrastructure/firebase/firebase_paths.dart';
import '../../domain/entities/activity_log.dart';
import '../../domain/repositories/activity_log_repository.dart';
import '../mappers/activity_log_firestore_mapper.dart';

class FirestoreActivityLogRepository implements ActivityLogRepository {
  FirestoreActivityLogRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  @override
  Stream<Result<List<ActivityLog>>> watchLogs({
    required StoreContext context,
    int limit = 100,
  }) async* {
    if (context.storeId.trim().isEmpty || context.userId.trim().isEmpty) {
      yield const FailureResult<List<ActivityLog>>(
        ValidationFailure(
          'A store and user are required to read the activity log.',
        ),
      );
      return;
    }

    try {
      final query = FirebasePaths.activityLogs(
        _firestore,
        context.storeId,
      ).orderBy('timestamp', descending: true).limit(limit);
      await for (final snapshot in query.snapshots()) {
        final logs = snapshot.docs
            .map(ActivityLogFirestoreMapper.fromSnapshot)
            .where((log) => log.storeId == context.storeId)
            .toList();
        yield Success<List<ActivityLog>>(logs);
      }
    } on FirebaseException catch (error) {
      yield FailureResult<List<ActivityLog>>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      yield FailureResult<List<ActivityLog>>(
        InfrastructureFailure(error.toString()),
      );
    }
  }
}
