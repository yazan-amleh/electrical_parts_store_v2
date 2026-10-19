class IdempotencyKey {
  const IdempotencyKey(this.value)
      : assert(value.length > 0, 'Idempotency key cannot be empty.');

  final String value;
}
