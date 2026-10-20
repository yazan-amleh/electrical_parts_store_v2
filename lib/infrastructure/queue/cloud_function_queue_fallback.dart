import 'package:cloud_functions/cloud_functions.dart' as firebase_functions;

import '../../core/commands/command_queue_repository.dart';
import '../../core/commands/queued_command.dart';
import '../../core/errors/failure.dart';
import '../../core/result/result.dart';
import '../../core/tenancy/store_context.dart';

abstract final class CloudFunctionQueueFallback {
  static bool isTransient(firebase_functions.FirebaseFunctionsException error) {
    return <String>{
      'aborted',
      'deadline-exceeded',
      'internal',
      'resource-exhausted',
      'unavailable',
    }.contains(error.code);
  }

  static Future<Failure?> enqueue({
    required CommandQueueRepository repository,
    required StoreContext context,
    required String commandId,
    required String operation,
    required String idempotencyKey,
    required Map<String, dynamic> payload,
  }) async {
    final result = await repository.save(
      context: context,
      command: QueuedCommand(
        id: commandId,
        storeId: context.storeId,
        createdBy: context.userId,
        operation: operation,
        idempotencyKey: idempotencyKey,
        payload: payload,
        createdAt: DateTime.now().toUtc(),
      ),
    );
    if (result is FailureResult<QueuedCommand>) {
      return result.failure;
    }
    return null;
  }
}
