import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/core/commands/command_queue_processor.dart';
import 'package:electrical_parts_store_v2/core/commands/queued_command.dart';
import 'package:electrical_parts_store_v2/core/errors/failure.dart';
import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/infrastructure/queue/in_memory_command_queue_repository.dart';

void main() {
  const context = StoreContext(storeId: 'store-1', userId: 'user-1');
  final createdAt = DateTime.utc(2026, 1, 1);

  QueuedCommand command() {
    return QueuedCommand(
      id: 'command-1',
      storeId: 'store-1',
      createdBy: 'user-1',
      operation: 'postSale',
      idempotencyKey: 'sale-1',
      payload: const <String, dynamic>{
        'storeId': 'store-1',
        'saleId': 'sale-1',
      },
      createdAt: createdAt,
    );
  }

  test('processes a command once and marks it completed', () async {
    final repository = InMemoryCommandQueueRepository();
    await repository.save(context: context, command: command());
    var calls = 0;

    final result = await const CommandQueueProcessor(
      repository: repository,
    ).drain(
      context: context,
      now: DateTime.utc(2026, 1, 1, 0, 1),
      executor: (queued) async {
        calls++;
        expect(queued.idempotencyKey, 'sale-1');
        return const Success<void>(null);
      },
    );

    expect(result, isA<Success<int>>());
    expect((result as Success<int>).value, 1);
    expect(calls, 1);
    expect(
      repository.getById('command-1')?.status,
      QueuedCommandStatus.completed,
    );
  });

  test('keeps infrastructure failures pending with a retry time', () async {
    final repository = InMemoryCommandQueueRepository();
    await repository.save(context: context, command: command());

    final now = DateTime.utc(2026, 1, 1, 0, 1);
    final result = await const CommandQueueProcessor(
      repository: repository,
    ).drain(
      context: context,
      now: now,
      executor: (queued) async {
        return const FailureResult<void>(
          InfrastructureFailure('Network is unavailable.'),
        );
      },
    );

    expect(result, isA<Success<int>>());
    expect((result as Success<int>).value, 0);
    final saved = repository.getById('command-1');
    expect(saved?.status, QueuedCommandStatus.pending);
    expect(saved?.attemptCount, 1);
    expect(saved?.lastError, 'Network is unavailable.');
    expect(saved?.nextAttemptAt?.isAfter(now), isTrue);
  });

  test('does not retry validation failures', () async {
    final repository = InMemoryCommandQueueRepository();
    await repository.save(context: context, command: command());

    final result = await const CommandQueueProcessor(
      repository: repository,
    ).drain(
      context: context,
      executor: (queued) async {
        return const FailureResult<void>(
          ValidationFailure('The command is invalid.'),
        );
      },
    );

    expect(result, isA<Success<int>>());
    expect(
      repository.getById('command-1')?.status,
      QueuedCommandStatus.failed,
    );
  });
}
