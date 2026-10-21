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

  Note copyWith({
    String? title,
    String? content,
    NoteType? type,
    NotePriority? priority,
    DateTime? updatedAt,
    DateTime? reminderAt,
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
      tags: tags ?? this.tags,
      isCompleted: isCompleted ?? this.isCompleted,
      isArchived: isArchived ?? this.isArchived,
      isStarred: isStarred ?? this.isStarred,
    );
  }
}
