import '../errors/failure.dart';

sealed class Result<T> {
  const Result();

  bool get isSuccess;
}

final class Success<T> extends Result<T> {
  const Success(this.value);

  final T value;

  @override
  bool get isSuccess => true;
}

final class FailureResult<T> extends Result<T> {
  const FailureResult(this.failure);

  final Failure failure;

  @override
  bool get isSuccess => false;
}
