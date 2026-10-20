class Money {
  const Money({required this.minorUnits, this.currency = 'ILS'});

  const Money.zero({this.currency = 'ILS'}) : minorUnits = 0;

  final int minorUnits;
  final String currency;

  bool get isZero => minorUnits == 0;
  bool get isNegative => minorUnits < 0;

  Money operator +(Money other) {
    _ensureSameCurrency(other);
    return Money(minorUnits: minorUnits + other.minorUnits, currency: currency);
  }

  Money operator -(Money other) {
    _ensureSameCurrency(other);
    return Money(minorUnits: minorUnits - other.minorUnits, currency: currency);
  }

  Money get absolute => Money(minorUnits: minorUnits.abs(), currency: currency);

  String get formatted {
    final sign = minorUnits < 0 ? '-' : '';
    final value = minorUnits.abs();
    final major = value ~/ 100;
    final cents = (value % 100).toString().padLeft(2, '0');
    return '$sign$major.$cents $currency';
  }

  void _ensureSameCurrency(Money other) {
    if (currency != other.currency) {
      throw ArgumentError('Cannot combine different currencies.');
    }
  }

  @override
  String toString() => formatted;

  @override
  bool operator ==(Object other) {
    return other is Money &&
        other.minorUnits == minorUnits &&
        other.currency == currency;
  }

  @override
  int get hashCode => Object.hash(minorUnits, currency);
}
