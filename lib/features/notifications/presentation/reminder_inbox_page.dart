import 'package:flutter/material.dart';

import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../domain/entities/note_reminder_notification.dart';
import '../domain/repositories/notification_repository.dart';

class ReminderInboxPage extends StatefulWidget {
  const ReminderInboxPage({
    required this.repository,
    required this.storeContext,
    super.key,
  });

  final NotificationRepository repository;
  final StoreContext storeContext;

  @override
  State<ReminderInboxPage> createState() => _ReminderInboxPageState();
}

class _ReminderInboxPageState extends State<ReminderInboxPage> {
  late Stream<Result<List<NoteReminderNotification>>> _reminders;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    _reminders = widget.repository.watchReminders(
      context: widget.storeContext,
    );
  }

  @override
  void didUpdateWidget(covariant ReminderInboxPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.storeContext.storeId != widget.storeContext.storeId ||
        oldWidget.storeContext.userId != widget.storeContext.userId) {
      _bind();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تذكيرات الملاحظات')),
        body: StreamBuilder<Result<List<NoteReminderNotification>>>(
          key: ValueKey(
            '${widget.storeContext.storeId}/${widget.storeContext.userId}',
          ),
          stream: _reminders,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text(snapshot.error.toString()));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final result = snapshot.data;
            if (result is FailureResult<List<NoteReminderNotification>>) {
              return Center(child: Text(result.failure.message));
            }
            final all = result is Success<List<NoteReminderNotification>>
                ? result.value
                    .where(
                      (item) =>
                          item.storeId == widget.storeContext.storeId &&
                          item.userId == widget.storeContext.userId,
                    )
                    .toList()
                : <NoteReminderNotification>[];
            if (all.isEmpty) {
              return const Center(
                child: Text('لا توجد تذكيرات مُرسلة أو مجدولة حتى الآن.'),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: all.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final reminder = all[index];
                final date = reminder.scheduledFor;
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.notifications_active_outlined),
                    title: Text(reminder.title),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(reminder.body),
                        Text(
                          'الموعد: ${date.day}/${date.month}/${date.year} '
                          '${date.hour.toString().padLeft(2, '0')}:'
                          '${date.minute.toString().padLeft(2, '0')}',
                        ),
                        Text(reminder.statusLabel),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
