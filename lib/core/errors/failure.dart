sealed class Failure {
  const Failure(this.message);

  final String message;
}

final class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

final class AuthorizationFailure extends Failure {
  const AuthorizationFailure(super.message);
}

final class ConflictFailure extends Failure {
  const ConflictFailure(super.message);
}

final class InfrastructureFailure extends Failure {
  const InfrastructureFailure(super.message);
}

final class QueuedFailure extends Failure {
  const QueuedFailure({required this.commandId})
    : super('The command was queued for later processing.');

  final String commandId;
}
