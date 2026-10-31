import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/note_reminder_notification.dart';

abstract interface class NotificationRepository {
  Stream<Result<List<NoteReminderNotification>>> watchReminders({
    required StoreContext context,
  });

  Future<Result<void>> registerCurrentDevice({
    required StoreContext context,
  });

  Future<Result<void>> unregisterCurrentDevice({
    required StoreContext context,
  });
}
