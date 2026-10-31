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
  test('V1 reminder recurrence calculates next daily and weekly date', () {
    Note make(ReminderRepeatType repeat) => Note(
          id: 'note-1',
          storeId: 'store-1',
          userId: 'user-1',
          title: 'متابعة',
          content: '',
          type: NoteType.appointment,
          priority: NotePriority.medium,
          createdAt: DateTime.utc(2026, 1, 1),
          reminderAt: DateTime.utc(2026, 1, 1, 9),
          reminderRepeat: repeat,
        );

    expect(
      make(ReminderRepeatType.daily).nextReminderAfter(
        DateTime.utc(2026, 1, 4, 10),
      ),
      DateTime.utc(2026, 1, 5, 9),
    );
    expect(
      make(ReminderRepeatType.weekly).nextReminderAfter(
        DateTime.utc(2026, 1, 8, 10),
      ),
      DateTime.utc(2026, 1, 15, 9),
    );
    expect(
      make(ReminderRepeatType.none).nextReminderAfter(
        DateTime.utc(2026, 1, 2),
      ),
      isNull,
    );
  });

  test('monthly repeats clamp short months without shifting anchor date', () {
    final note = Note(
      id: 'note-month',
      storeId: 'store-1',
      userId: 'user-1',
      title: 'تسوية شهرية',
      content: '',
      type: NoteType.reminder,
      priority: NotePriority.high,
      createdAt: DateTime.utc(2026, 1, 1),
      reminderAt: DateTime.utc(2026, 1, 31, 10),
      reminderRepeat: ReminderRepeatType.monthly,
    );
    expect(
      note.nextReminderAfter(DateTime.utc(2026, 2, 1)),
      DateTime.utc(2026, 2, 28, 10),
    );
    expect(
      note.nextReminderAfter(DateTime.utc(2026, 3, 1)),
      DateTime.utc(2026, 3, 31, 10),
    );
    final cleared = note.copyWith(clearReminder: true);
    expect(cleared.reminderAt, isNull);
    expect(cleared.reminderRepeat, ReminderRepeatType.none);
  });

}
