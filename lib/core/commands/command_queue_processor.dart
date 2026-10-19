import '../errors/failure.dart';
import '../result/result.dart';
import '../tenancy/store_context.dart';
import 'command_queue_repository.dart';
import 'queued_command.dart';

typedef QueuedCommandExecutor = Future<Result<void>> Function(
  QueuedCommand command,
);

class CommandQueueProcessor {
  const CommandQueueProcessor({
    required CommandQueueRepository repository,
    this.maxAttempts = 5,
  }) : _repository = repository;

  final CommandQueueRepository _repository;
  final int maxAttempts;

  Future<Result<int>> drain({
    required StoreContext context,
    required QueuedCommandExecutor executor,
    DateTime? now,
    int limit = 20,
  }) async {
    if (maxAttempts <= 0) {
      return const FailureResult<int>(
        ValidationFailure('Command queue max attempts must be positive.'),
      );
    }
    if (limit <= 0 || limit > 100) {
      return const FailureResult<int>(
        ValidationFailure('Command queue limit must be between 1 and 100.'),
      );
    }

    final currentTime = (now ?? DateTime.now()).toUtc();
    final dueResult = await _repository.getDue(
      context: context,
      now: currentTime,
      limit: limit,
    );
    if (dueResult is FailureResult<List<QueuedCommand>>) {
      return FailureResult<int>(dueResult.failure);
    }

    final commands = (dueResult as Success<List<QueuedCommand>>).value;
    var completedCount = 0;

    for (final command in commands) {
      final processingResult = await _repository.save(
        context: context,
        command: command.processing(now: currentTime),
      );
      if (processingResult is FailureResult<QueuedCommand>) {
        return FailureResult<int>(processingResult.failure);
      }

      final execution = await executor(command);
      if (execution is Success<void>) {
        final completedResult = await _repository.save(
          context: context,
          command: command.processing(now: currentTime).completed(),
        );
        if (completedResult is FailureResult<QueuedCommand>) {
          return FailureResult<int>(completedResult.failure);
        }
        completedCount++;
        continue;
      }

      final failure = (execution as FailureResult<void>).failure;
      final updatedCommand = _failureCommand(
        command: command,
        failure: failure,
        now: currentTime,
      );
      final failureResult = await _repository.save(
        context: context,
        command: updatedCommand,
      );
      if (failureResult is FailureResult<QueuedCommand>) {
        return FailureResult<int>(failureResult.failure);
      }
    }

    return Success<int>(completedCount);
  }

  QueuedCommand _failureCommand({
    required QueuedCommand command,
    required Failure failure,
    required DateTime now,
  }) {
    final attempt = command.attemptCount + 1;
    final retryable = failure is InfrastructureFailure &&
        attempt < maxAttempts;
    if (!retryable) {
      return command.processing(now: now).failed(failure.message);
    }

    final delaySeconds = (attempt * 15).clamp(15, 300).toInt();
    return command.processing(now: now).retryAt(
          now.add(Duration(seconds: delaySeconds)),
          failure.message,
        );
  }
}
