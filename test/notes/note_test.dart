import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/features/notes/domain/entities/note.dart';
import 'package:electrical_parts_store_v2/features/notes/domain/enums/note_enums.dart';

void main() {
  test('sort metadata and overdue state stay deterministic', () {
    final note = Note(
      id: 'note-1',
      storeId: 'store-1',
      userId: 'user-1',
      title: 'متابعة عميل',
      content: 'اتصل به غداً',
      type: NoteType.customer,
      priority: NotePriority.high,
      createdAt: DateTime.utc(2026, 1, 1),
      reminderAt: DateTime.now().subtract(const Duration(days: 1)),
      tags: const ['متابعة'],
    );

    expect(note.priority, NotePriority.high);
    expect(note.isOverdue, isTrue);
    expect(note.copyWith(isStarred: true).isStarred, isTrue);
  });

  test('rejects unsafe note identifiers', () {
    expect(
      () => Note(
        id: 'notes/note-1',
        storeId: 'store-1',
        userId: 'user-1',
        title: 'عنوان',
        content: '',
        type: NoteType.general,
        priority: NotePriority.medium,
        createdAt: DateTime.utc(2026, 1, 1),
      ),
      throwsArgumentError,
    );
  });
}
