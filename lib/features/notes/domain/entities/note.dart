import '../enums/note_enums.dart';

class Note {
  Note({
    required this.id,
    required this.storeId,
    required this.userId,
    required this.title,
    required this.content,
    required this.type,
    required this.priority,
    required DateTime createdAt,
    this.updatedAt,
    this.reminderAt,
    this.reminderRepeat = ReminderRepeatType.none,
    List<String>? tags,
    this.isCompleted = false,
    this.isArchived = false,
    this.isStarred = false,
  })  : createdAt = createdAt.toUtc(),
        tags = List.unmodifiable(tags ?? const <String>[]) {
    if (id.trim().isEmpty ||
        storeId.trim().isEmpty ||
        userId.trim().isEmpty ||
        title.trim().isEmpty) {
      throw ArgumentError('Note identity, title and ownership are required.');
    }
    if (id.contains('/') || storeId.contains('/') || userId.contains('/')) {
      throw ArgumentError('Note identifiers cannot contain a slash.');
    }
  }

  final String id;
  final String storeId;
  final String userId;
  final String title;
  final String content;
  final NoteType type;
  final NotePriority priority;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? reminderAt;
  final ReminderRepeatType reminderRepeat;
  final List<String> tags;
  final bool isCompleted;
  final bool isArchived;
  final bool isStarred;

  bool get isOverdue {
    return reminderAt != null &&
        reminderAt!.isBefore(DateTime.now()) &&
        !isCompleted &&
        !isArchived;
  }

  /// The next scheduled occurrence after [moment], derived from the original
  /// UTC reminder without mutating any stored transaction or note.
  /// Repetition scheduling is metadata; delivery requires a separate worker.
  DateTime? nextReminderAfter(DateTime moment) {
    final first = reminderAt?.toUtc();
    if (first == null || isCompleted || isArchived) {
      return null;
    }
    final now = moment.toUtc();
    if (!first.isBefore(now)) {
      return first;
    }
    if (reminderRepeat == ReminderRepeatType.none) {
      return null;
    }
    if (reminderRepeat == ReminderRepeatType.daily ||
        reminderRepeat == ReminderRepeatType.weekly) {
      final step = reminderRepeat == ReminderRepeatType.daily ? 1 : 7;
      final elapsed = now.difference(first).inDays;
      var candidate = first.add(Duration(days: (elapsed ~/ step) * step));
      if (candidate.isBefore(now)) {
        candidate = candidate.add(Duration(days: step));
      }
      return candidate;
    }
    final firstMonth = first.year * 12 + first.month - 1;
    final nowMonth = now.year * 12 + now.month - 1;
    var offset = nowMonth - firstMonth;
    DateTime occurrence(int months) {
      final year = first.year + ((first.month - 1 + months) ~/ 12);
      final month = ((first.month - 1 + months) % 12) + 1;
      final lastDay = DateTime.utc(year, month + 1, 0).day;
      final day = first.day < lastDay ? first.day : lastDay;
      return DateTime.utc(
        year,
        month,
        day,
        first.hour,
        first.minute,
        first.second,
        first.millisecond,
        first.microsecond,
      );
    }

    var candidate = occurrence(offset);
    if (candidate.isBefore(now)) {
      offset++;
      candidate = occurrence(offset);
    }
    return candidate;
  }

  Note copyWith({
    String? title,
    String? content,
    NoteType? type,
    NotePriority? priority,
    DateTime? updatedAt,
    DateTime? reminderAt,
    ReminderRepeatType? reminderRepeat,
    bool clearReminder = false,
    List<String>? tags,
    bool? isCompleted,
    bool? isArchived,
    bool? isStarred,
  }) {
    return Note(
      id: id,
      storeId: storeId,
      userId: userId,
      title: title ?? this.title,
      content: content ?? this.content,
      type: type ?? this.type,
      priority: priority ?? this.priority,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reminderAt: clearReminder ? null : reminderAt ?? this.reminderAt,
      reminderRepeat: clearReminder
          ? ReminderRepeatType.none
          : reminderRepeat ?? this.reminderRepeat,
      tags: tags ?? this.tags,
      isCompleted: isCompleted ?? this.isCompleted,
      isArchived: isArchived ?? this.isArchived,
      isStarred: isStarred ?? this.isStarred,
    );
  }
}
