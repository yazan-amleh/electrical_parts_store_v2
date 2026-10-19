import '../../../../core/money/money.dart';

import 'journal_line.dart';

class JournalEntry {
  JournalEntry({
    required this.id,
    required this.storeId,
    required this.idempotencyKey,
    required this.postedAt,
    required this.sourceType,
    required List<JournalLine> lines,
    this.description,
  }) : lines = List.unmodifiable(lines) {
    validateForPosting();
  }

  final String id;
  final String storeId;
  final String idempotencyKey;
  final DateTime postedAt;
  final String sourceType;
  final List<JournalLine> lines;
  final String? description;

  Money get totalDebit {
    _ensureHasLines();
    return lines.fold(
      Money.zero(currency: lines.first.debit.currency),
      (sum, line) => sum + line.debit,
    );
  }

  Money get totalCredit {
    _ensureHasLines();
    return lines.fold(
      Money.zero(currency: lines.first.credit.currency),
      (sum, line) => sum + line.credit,
    );
  }

  bool get isBalanced => totalDebit == totalCredit;

  void validateForPosting() {
    if (id.trim().isEmpty) {
      throw ArgumentError('Journal entry id is required.');
    }
    if (storeId.trim().isEmpty) {
      throw ArgumentError('Journal entry store id is required.');
    }
    if (idempotencyKey.trim().isEmpty) {
      throw ArgumentError('Journal entry idempotency key is required.');
    }
    if (sourceType.trim().isEmpty) {
      throw ArgumentError('Journal entry source type is required.');
    }
    if (lines.length < 2) {
      throw ArgumentError('A journal entry requires at least two lines.');
    }
    if (!isBalanced) {
      throw ArgumentError('Journal entry must be balanced.');
    }
  }

  void _ensureHasLines() {
    if (lines.isEmpty) {
      throw ArgumentError('Journal entry must contain lines.');
    }
  }
}
