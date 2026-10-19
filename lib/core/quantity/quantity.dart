class Quantity implements Comparable<Quantity> {
  const Quantity.fromMilliUnits(this.milliUnits);

  factory Quantity.fromDouble(double value) {
    if (!value.isFinite) {
      throw ArgumentError('Quantity must be finite.');
    }
    return Quantity.fromMilliUnits((value * scale).round());
  }

  factory Quantity.fromString(String value) {
    final parsed = double.tryParse(value.trim());
    if (parsed == null) {
      throw ArgumentError('Quantity must be numeric.');
    }
    return Quantity.fromDouble(parsed);
  }

  static const int scale = 1000;

  final int milliUnits;

  double get value => milliUnits / scale;

  bool get isZero => milliUnits == 0;
  bool get isNegative => milliUnits < 0;

  Quantity operator +(Quantity other) {
    return Quantity.fromMilliUnits(milliUnits + other.milliUnits);
  }

  Quantity operator -(Quantity other) {
    return Quantity.fromMilliUnits(milliUnits - other.milliUnits);
  }

  @override
  int compareTo(Quantity other) {
    return milliUnits.compareTo(other.milliUnits);
  }

  String get formatted {
    final raw = value.toStringAsFixed(3);
    return raw
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  @override
  bool operator ==(Object other) {
    return other is Quantity && other.milliUnits == milliUnits;
  }

  @override
  int get hashCode => milliUnits.hashCode;

  @override
  String toString() => formatted;
}
