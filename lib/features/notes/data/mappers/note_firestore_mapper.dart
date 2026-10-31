import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/note.dart';
import '../../domain/enums/note_enums.dart';

class NoteFirestoreMapper {
  static Note fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return Note(
      id: snapshot.id,
      storeId: data['storeId'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      title: data['title'] as String? ?? '',
      content: data['content'] as String? ?? '',
      type: _noteType(data['type'] as String?),
      priority: _notePriority(data['priority'] as String?),
      createdAt: _date(data['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt: _date(data['updatedAt']),
      reminderAt: _date(data['reminderAt']),
      reminderRepeat: _reminderRepeat(data['reminderRepeat'] as String?),
      tags: _strings(data['tags']),
      isCompleted: data['isCompleted'] as bool? ?? false,
      isArchived: data['isArchived'] as bool? ?? false,
      isStarred: data['isStarred'] as bool? ?? false,
    );
  }

  static Map<String, dynamic> toMap(Note note) {
    return <String, dynamic>{
      'storeId': note.storeId,
      'userId': note.userId,
      'title': note.title,
      'content': note.content,
      'type': note.type.name,
      'priority': note.priority.name,
      'createdAt': Timestamp.fromDate(note.createdAt),
      'updatedAt':
          note.updatedAt == null ? null : Timestamp.fromDate(note.updatedAt!),
      'reminderAt':
          note.reminderAt == null ? null : Timestamp.fromDate(note.reminderAt!),
      'reminderRepeat': note.reminderRepeat.name,
      'tags': note.tags,
      'isCompleted': note.isCompleted,
      'isArchived': note.isArchived,
      'isStarred': note.isStarred,
    };
  }

  static NoteType _noteType(String? value) {
    return NoteType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => NoteType.general,
    );
  }

  static NotePriority _notePriority(String? value) {
    return NotePriority.values.firstWhere(
      (priority) => priority.name == value,
      orElse: () => NotePriority.medium,
    );
  }

  static ReminderRepeatType _reminderRepeat(String? value) {
    return ReminderRepeatType.values.firstWhere(
      (repeat) => repeat.name == value,
      orElse: () => ReminderRepeatType.none,
    );
  }

  static DateTime? _date(Object? value) {
    if (value is Timestamp) {
      return value.toDate().toUtc();
    }
    if (value is DateTime) {
      return value.toUtc();
    }
    if (value is String) {
      return DateTime.tryParse(value)?.toUtc();
    }
    return null;
  }

  static List<String> _strings(Object? value) {
    if (value is! Iterable) {
      return const <String>[];
    }
    return value.whereType<String>().toList();
  }
}
