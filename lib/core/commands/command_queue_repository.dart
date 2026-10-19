import '../result/result.dart';
import '../tenancy/store_context.dart';
import 'queued_command.dart';

abstract interface class CommandQueueRepository {
  Future<Result<QueuedCommand>> save({
    required StoreContext context,
    required QueuedCommand command,
  });

  Future<Result<List<QueuedCommand>>> getDue({
    required StoreContext context,
    DateTime? now,
    int limit = 20,
  });
}
