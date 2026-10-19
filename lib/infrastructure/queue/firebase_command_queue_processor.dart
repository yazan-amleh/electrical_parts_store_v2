import 'package:cloud_functions/cloud_functions.dart' as firebase_functions;

import '../../core/commands/command_queue_processor.dart';
import '../../core/errors/failure.dart';
import '../../core/commands/command_queue_repository.dart';
import '../../core/result/result.dart';
import '../../core/tenancy/store_context.dart';

class FirebaseCommandQueueProcessor {
  FirebaseCommandQueueProcessor({
    required firebase_functions.FirebaseFunctions functions,
    required CommandQueueRepository repository,
    CommandQueueProcessor processor = const CommandQueueProcessor,
  })  : _functions = functions,
        _processor = processor,
        _repository = repository;

  final firebase_functions.FirebaseFunctions _functions;
  final CommandQueueProcessor _processor;
  final CommandQueueRepository _repository;

  Future<Result<int>> drain({
    required StoreContext context,
    DateTime? now,
    int limit = 20,
  }) {
    return _processor.drain(
      context: context,
      now: now,
      limit: limit,
      executor: (command) async {
        try {
          final callable = _functions.httpsCallable(command.operation);
          await callable.call<Map<String, dynamic>>(command.payload);
          return const Success<void>(null);
        } on firebase_functions.FirebaseFunctionsException catch (error) {
          return FailureResult<void>(_mapFailure(error));
        } catch (error) {
          return FailureResult<void>(
            InfrastructureFailure(error.toString()),
          );
        }
      },
    );
  }

  Failure _mapFailure(
    firebase_functions.FirebaseFunctionsException error,
  ) {
    switch (error.code) {
      case 'permission-denied':
      case 'unauthenticated':
        return AuthorizationFailure(
          error.message ?? 'Queued command is not authorized.',
        );
      case 'invalid-argument':
      case 'failed-precondition':
        return ValidationFailure(
          error.message ?? 'Queued command is invalid.',
        );
      case 'already-exists':
        return ConflictFailure(
          error.message ?? 'Queued command conflicts with existing data.',
        );
      default:
        return InfrastructureFailure(error.message ?? error.code);
    }
  }
}
