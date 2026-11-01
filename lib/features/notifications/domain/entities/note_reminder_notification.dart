class NoteReminderNotification {
  const NoteReminderNotification({
    required this.id,
    required this.storeId,
    required this.userId,
    required this.noteId,
    required this.title,
    required this.body,
    required this.scheduledFor,
    required this.status,
  });

  final String id;
  final String storeId;
  final String userId;
  final String noteId;
  final String title;
  final String body;
  final DateTime scheduledFor;
  final String status;

  String get statusLabel {
    switch (status) {
      case 'sent':
        return 'تم الإرسال';
      case 'noDevice':
        return 'لم يُسجّل جهاز للإشعارات';
      case 'queued':
      case 'sending':
        return 'قيد الإرسال';
      case 'failed':
        return 'تعذر الإرسال';
      case 'skipped':
        return 'أُلغي';
      default:
        return 'غير محدد';
    }
  }
}
