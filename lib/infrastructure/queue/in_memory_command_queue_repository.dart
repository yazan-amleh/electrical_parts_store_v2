import '../../core/commands/command_queue_repository.dart';
import '../../core/commands/queued_command.dart';
import '../../core/errors/failure.dart';
import '../../core/result/result.dart';
import '../../core/tenancy/store_context.dart';

class InMemoryCommandQueueRepository implements CommandQueueRepository {
  final Map<String, QueuedCommand> _commands = <String, QueuedCommand>{};

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

    final existing = _commands[command.id];
    if (existing != null && existing.idempotencyKey != command.idempotencyKey) {
      return const FailureResult<QueuedCommand>(
        ConflictFailure('Queued command id is already assigned.'),
      );
    }

    _commands[command.id] = command;
    return Success<QueuedCommand>(command);
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

    final currentTime = (now ?? DateTime.now()).toUtc();
    final commands = _commands.values
        .where(
          (command) =>
              command.storeId == context.storeId &&
              command.createdBy == context.userId &&
              command.isDue(currentTime),
        )
        .toList()
      ..sort(
        (first, second) => first.createdAt.compareTo(second.createdAt),
      );

    return Success<List<QueuedCommand>>(
      commands.take(limit).toList(growable: false),
    );
  }

  QueuedCommand? getById(String id) => _commands[id];
}
