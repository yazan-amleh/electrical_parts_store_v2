enum NoteType {
  general,
  customer,
  appointment,
  employee,
  task,
  reminder,
}

extension NoteTypeLabels on NoteType {
  String get arabicLabel {
    switch (this) {
      case NoteType.general:
        return 'عامة';
      case NoteType.customer:
        return 'عميل';
      case NoteType.appointment:
        return 'موعد';
      case NoteType.employee:
        return 'موظف';
      case NoteType.task:
        return 'مهمة';
      case NoteType.reminder:
        return 'تذكير';
    }
  }
}

enum NotePriority {
  low,
  medium,
  high,
  urgent,
}

extension NotePriorityLabels on NotePriority {
  String get arabicLabel {
    switch (this) {
      case NotePriority.low:
        return 'منخفضة';
      case NotePriority.medium:
        return 'متوسطة';
      case NotePriority.high:
        return 'عالية';
      case NotePriority.urgent:
        return 'عاجلة';
    }
  }
}

enum ReminderRepeatType { none, daily, weekly, monthly }

extension ReminderRepeatTypeLabels on ReminderRepeatType {
  String get arabicLabel {
    switch (this) {
      case ReminderRepeatType.none:
        return 'بدون تكرار';
      case ReminderRepeatType.daily:
        return 'يوميًا';
      case ReminderRepeatType.weekly:
        return 'أسبوعيًا';
      case ReminderRepeatType.monthly:
        return 'شهريًا';
    }
  }
}
