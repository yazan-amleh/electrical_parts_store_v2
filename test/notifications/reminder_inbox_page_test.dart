import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/notifications/domain/entities/note_reminder_notification.dart';
import 'package:electrical_parts_store_v2/features/notifications/domain/repositories/notification_repository.dart';
import 'package:electrical_parts_store_v2/features/notifications/presentation/reminder_inbox_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _InboxRepository implements NotificationRepository {
  final List<StoreContext> reads = [];

  @override
  Stream<Result<List<NoteReminderNotification>>> watchReminders({
    required StoreContext context,
  }) {
    reads.add(context);
    return Stream<Result<List<NoteReminderNotification>>>.value(
      Success<List<NoteReminderNotification>>([
        NoteReminderNotification(
          id: 'event-one',
          storeId: context.storeId,
          userId: context.userId,
          noteId: 'note-1',
          title: 'موعد مراجعة الفواتير',
          body: 'تذكير بمراجعة العمليات',
          scheduledFor: DateTime.utc(2026, 10, 31, 10),
          status: 'sent',
        ),
        NoteReminderNotification(
          id: 'foreign-event',
          storeId: 'other-store',
          userId: context.userId,
          noteId: 'foreign',
          title: 'تذكير متجر آخر',
          body: 'خاص',
          scheduledFor: DateTime.utc(2026, 10, 31, 11),
          status: 'sent',
        ),
      ]),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _page(_InboxRepository repo, String storeId) {
  return MaterialApp(
    home: ReminderInboxPage(
      repository: repo,
      storeContext: StoreContext(storeId: storeId, userId: 'user-1'),
    ),
  );
}

void main() {
  testWidgets('reminder inbox filters other-store records and shows delivery', (
    tester,
  ) async {
    final repository = _InboxRepository();
    await tester.pumpWidget(_page(repository, 'store-a'));
    await tester.pumpAndSettle();
    expect(find.text('موعد مراجعة الفواتير'), findsOneWidget);
    expect(find.text('تم الإرسال'), findsOneWidget);
    expect(find.text('تذكير متجر آخر'), findsNothing);
    expect(repository.reads.single.storeId, 'store-a');

    await tester.pumpWidget(_page(repository, 'store-b'));
    await tester.pumpAndSettle();
    expect(repository.reads.last.storeId, 'store-b');
    expect(find.text('تذكير متجر آخر'), findsNothing);
  });
}
