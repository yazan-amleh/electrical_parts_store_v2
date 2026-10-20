import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/commands/command_queue_repository.dart';
import '../../core/commands/queued_command.dart';
import '../../core/errors/failure.dart';
import '../../core/result/result.dart';
import '../../core/tenancy/store_context.dart';
import '../firebase/firebase_paths.dart';
import 'queued_command_firestore_mapper.dart';

class FirestoreCommandQueueRepository implements CommandQueueRepository {
  FirestoreCommandQueueRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  @override
  Future<Result<QueuedCommand>> save({
    required StoreContext context,
    required QueuedCommand command,
  }) async {
    if (command.storeId != context.storeId ||
        command.createdBy != context.userId) {
      return const FailureResult<QueuedCommand>(
        AuthorizationFailure(
          'Queued command does not belong to the active user and store.',
        ),
      );
    }

    try {
      await FirebasePaths.commandOutbox(
        _firestore,
        context.storeId,
      ).doc(command.id).set(QueuedCommandFirestoreMapper.toMap(command));
      return Success<QueuedCommand>(command);
    } on FirebaseException catch (error) {
      return FailureResult<QueuedCommand>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<QueuedCommand>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<List<QueuedCommand>>> getDue({
    required StoreContext context,
    DateTime? now,
    int limit = 20,
  }) async {
    if (limit <= 0 || limit > 100) {
      return const FailureResult<List<QueuedCommand>>(
        ValidationFailure('Command queue limit must be between 1 and 100.'),
      );
    }

    try {
      final snapshot =
          await FirebasePaths.commandOutbox(_firestore, context.storeId)
              .where('createdBy', isEqualTo: context.userId)
              .where(
                'status',
                whereIn: <String>[
                  QueuedCommandStatus.pending.name,
                  QueuedCommandStatus.processing.name,
                ],
              )
              .orderBy('createdAt')
              .limit(limit)
              .get();

      final currentTime = (now ?? DateTime.now()).toUtc();
      return Success<List<QueuedCommand>>(
        snapshot.docs
            .map(QueuedCommandFirestoreMapper.fromSnapshot)
            .where((command) => command.isDue(currentTime))
            .toList(growable: false),
      );
    } on FirebaseException catch (error) {
      return FailureResult<List<QueuedCommand>>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<List<QueuedCommand>>(
        InfrastructureFailure(error.toString()),
      );
    }
  }
}
