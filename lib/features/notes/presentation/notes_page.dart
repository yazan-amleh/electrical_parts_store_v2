import 'package:flutter/material.dart';

import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../domain/entities/note.dart';
import '../domain/enums/note_enums.dart';
import '../domain/repositories/note_repository.dart';

class NotesPage extends StatefulWidget {
  const NotesPage({
    required this.repository,
    required this.user,
    required this.membership,
    super.key,
  });

  final NoteRepository repository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<NotesPage> createState() => _NotesPageState();
}

enum _NotesView { active, starred, archived }

class _NotesPageState extends State<NotesPage> {
  late StoreContext _context;
  late Future<Result<List<Note>>> _notesFuture;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  _NotesView _view = _NotesView.active;
  NoteType? _selectedType;
  NotePriority? _selectedPriority;
  bool _showCompletedTasks = true;

  @override
  void initState() {
    super.initState();
    _context = StoreContext(
      storeId: widget.membership.storeId,
      userId: widget.user.id,
    );
    _notesFuture = _loadNotes();
    _searchController.addListener(_handleSearchChanged);
  }

  void _handleSearchChanged() {
    if (mounted) {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    }
  }

  bool _isCurrentContext(StoreContext actionContext) {
    return actionContext.storeId == _context.storeId &&
        actionContext.userId == _context.userId;
  }

  @override
  void didUpdateWidget(covariant NotesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.id != widget.user.id ||
        oldWidget.membership.storeId != widget.membership.storeId ||
        oldWidget.repository != widget.repository) {
      _searchController.removeListener(_handleSearchChanged);
      _searchController.clear();
      _searchController.addListener(_handleSearchChanged);
      _searchQuery = '';
      _view = _NotesView.active;
      _selectedType = null;
      _selectedPriority = null;
      _showCompletedTasks = true;
      _context = StoreContext(
        storeId: widget.membership.storeId,
        userId: widget.user.id,
      );
      _notesFuture = _loadNotes();
    }
  }

  Future<Result<List<Note>>> _loadNotes() {
    return widget.repository.getNotes(
      context: _context,
      includeArchived: _view != _NotesView.active,
      starredOnly: _view == _NotesView.starred,
    );
  }

  void _reload() {
    setState(() {
      _notesFuture = _loadNotes();
    });
  }

  Future<void> _editNote([Note? note]) async {
    final actionContext = _context;
    final draft = await showDialog<_NoteDraft>(
      context: context,
      builder: (context) => _NoteDialog(note: note),
    );
    if (draft == null || !mounted || !_isCurrentContext(actionContext)) {
      return;
    }

    final now = DateTime.now().toUtc();
    final candidate = note == null
        ? Note(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            storeId: actionContext.storeId,
            userId: actionContext.userId,
            title: draft.title,
            content: draft.content,
            type: draft.type,
            priority: draft.priority,
            createdAt: now,
            tags: draft.tags,
            reminderAt: draft.reminderAt,
            reminderRepeat: draft.reminderRepeat,
          )
        : note.copyWith(
            title: draft.title,
            content: draft.content,
            type: draft.type,
            priority: draft.priority,
            tags: draft.tags,
            updatedAt: now,
            reminderAt: draft.reminderAt,
            reminderRepeat: draft.reminderRepeat,
            clearReminder: draft.clearReminder,
          );

    final result = await widget.repository.saveNote(
      context: actionContext,
      note: candidate,
    );
    if (!mounted || !_isCurrentContext(actionContext)) {
      return;
    }
    if (result is FailureResult<void>) {
      _showMessage(result.failure.message);
    } else {
      _showMessage('تم حفظ الملاحظة');
      _reload();
    }
  }

  Future<void> _updateNote(Note updated) async {
    final actionContext = _context;
    if (updated.storeId != actionContext.storeId ||
        updated.userId != actionContext.userId) {
      return;
    }
    final result = await widget.repository.saveNote(
      context: actionContext,
      note: updated,
    );
    if (!mounted || !_isCurrentContext(actionContext)) {
      return;
    }
    if (result is FailureResult<void>) {
      _showMessage(result.failure.message);
    } else {
      _reload();
    }
  }

  Future<void> _showNoteDetails(Note note) async {
    final actionContext = _context;
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final localized = MaterialLocalizations.of(dialogContext);
        String formatDate(DateTime date) {
          final local = date.toLocal();
          return '${localized.formatMediumDate(local)} '
              '${localized.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
        }

        return AlertDialog(
          title: Text(note.title),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 480,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SelectableText(
                      note.content.isEmpty ? 'بدون محتوى' : note.content),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      Chip(label: Text(note.type.arabicLabel)),
                      Chip(label: Text(note.priority.arabicLabel)),
                      if (note.isStarred) const Chip(label: Text('مميزة')),
                      if (note.isArchived) const Chip(label: Text('مؤرشفة')),
                      if (note.isCompleted) const Chip(label: Text('مكتملة')),
                    ],
                  ),
                  if (note.tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('الوسوم: ${note.tags.join(', ')}'),
                  ],
                  const SizedBox(height: 8),
                  Text('تاريخ الإنشاء: ${formatDate(note.createdAt)}'),
                  if (note.updatedAt != null)
                    Text('آخر تعديل: ${formatDate(note.updatedAt!)}'),
                  if (note.reminderAt != null) ...[
                    const SizedBox(height: 8),
                    Text('موعد المتابعة: ${formatDate(note.reminderAt!)}'),
                    if (note.reminderRepeat != ReminderRepeatType.none)
                      Text('التكرار: ${note.reminderRepeat.arabicLabel}'),
                    if (note.reminderRepeat != ReminderRepeatType.none &&
                        note.nextReminderAfter(DateTime.now()) != null)
                      Text(
                        'الموعد القادم: ${formatDate(note.nextReminderAfter(DateTime.now())!)}',
                      ),
                    const Text(
                      'الموعد محفوظ، ولا يُرسل إشعار تلقائي من هذه الشاشة.',
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('delete'),
              child: const Text('حذف'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('edit'),
              child: const Text('تعديل'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('إغلاق'),
            ),
          ],
        );
      },
    );
    if (!mounted || !_isCurrentContext(actionContext)) {
      return;
    }
    if (action == 'edit') {
      await _editNote(note);
    } else if (action == 'delete') {
      await _deleteNote(note);
    }
  }

  Future<void> _deleteNote(Note note) async {
    final actionContext = _context;
    if (note.storeId != actionContext.storeId ||
        note.userId != actionContext.userId) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل تريد حذف الملاحظة "${note.title}" نهائيًا؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || !_isCurrentContext(actionContext)) {
      return;
    }
    final result = await widget.repository.deleteNote(
      context: actionContext,
      note: note,
    );
    if (!mounted || !_isCurrentContext(actionContext)) {
      return;
    }
    if (result is FailureResult<void>) {
      _showMessage(result.failure.message);
    } else {
      _showMessage('تم حذف الملاحظة');
      _reload();
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  List<Note> _visibleNotes(List<Note> notes) {
    return notes.where((note) {
      if (_view == _NotesView.active && note.isArchived) {
        return false;
      }
      if (_view == _NotesView.starred && !note.isStarred) {
        return false;
      }
      if (_view == _NotesView.archived && !note.isArchived) {
        return false;
      }
      if (_selectedType != null && note.type != _selectedType) {
        return false;
      }
      if (_selectedPriority != null && note.priority != _selectedPriority) {
        return false;
      }
      if (!_showCompletedTasks &&
          _selectedType == NoteType.task &&
          note.isCompleted) {
        return false;
      }
      if (_searchQuery.isEmpty) {
        return true;
      }
      return note.title.toLowerCase().contains(_searchQuery) ||
          note.content.toLowerCase().contains(_searchQuery) ||
          note.tags.any((tag) => tag.toLowerCase().contains(_searchQuery));
    }).toList();
  }

  Widget _viewChip(_NotesView view, String label) {
    return ChoiceChip(
      selected: _view == view,
      label: Text(label),
      onSelected: (_) {
        if (_view == view) {
          return;
        }
        setState(() {
          _view = view;
          _notesFuture = _loadNotes();
        });
      },
    );
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ملاحظاتي'),
          actions: [
            IconButton(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث الملاحظات',
            ),
            IconButton(
              onPressed: () => _editNote(),
              icon: const Icon(Icons.add),
              tooltip: 'ملاحظة جديدة',
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'ابحث في الملاحظات',
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _viewChip(_NotesView.active, 'النشطة'),
                  const SizedBox(width: 8),
                  _viewChip(_NotesView.starred, 'المميزة بنجمة'),
                  const SizedBox(width: 8),
                  _viewChip(_NotesView.archived, 'المؤرشفة'),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  DropdownButton<NoteType?>(
                    value: _selectedType,
                    hint: const Text('النوع'),
                    items: [
                      const DropdownMenuItem<NoteType?>(
                        value: null,
                        child: Text('كل الأنواع'),
                      ),
                      ...NoteType.values.map(
                        (type) => DropdownMenuItem<NoteType?>(
                          value: type,
                          child: Text(type.arabicLabel),
                        ),
                      ),
                    ],
                    onChanged: (type) {
                      setState(() => _selectedType = type);
                    },
                  ),
                  const SizedBox(width: 16),
                  DropdownButton<NotePriority?>(
                    value: _selectedPriority,
                    hint: const Text('الأولوية'),
                    items: [
                      const DropdownMenuItem<NotePriority?>(
                        value: null,
                        child: Text('كل الأولويات'),
                      ),
                      ...NotePriority.values.map(
                        (priority) => DropdownMenuItem<NotePriority?>(
                          value: priority,
                          child: Text(priority.arabicLabel),
                        ),
                      ),
                    ],
                    onChanged: (priority) {
                      setState(() => _selectedPriority = priority);
                    },
                  ),
                  if (_selectedType == NoteType.task) ...[
                    const SizedBox(width: 16),
                    FilterChip(
                      label: const Text('عرض المكتملة'),
                      selected: _showCompletedTasks,
                      onSelected: (value) {
                        setState(() => _showCompletedTasks = value);
                      },
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<Result<List<Note>>>(
                key: ValueKey('${_context.storeId}/${_context.userId}'),
                future: _notesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text(snapshot.error.toString()));
                  }
                  final result = snapshot.data;
                  if (result is FailureResult<List<Note>>) {
                    return Center(child: Text(result.failure.message));
                  }
                  final notes = result is Success<List<Note>>
                      ? _visibleNotes(result.value)
                      : const <Note>[];
                  if (notes.isEmpty) {
                    return const Center(child: Text('لا توجد ملاحظات بعد.'));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: notes.length,
                    itemBuilder: (context, index) {
                      final note = notes[index];
                      return Card(
                        child: ListTile(
                          onTap: () => _showNoteDetails(note),
                          leading: CircleAvatar(
                            child: Icon(note.isCompleted
                                ? Icons.check
                                : Icons.notes_outlined),
                          ),
                          title: Text(note.title),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (note.content.trim().isNotEmpty)
                                Text(
                                  note.content,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 4,
                                children: [
                                  Chip(label: Text(note.type.arabicLabel)),
                                  Chip(
                                    label: Text(note.priority.arabicLabel),
                                  ),
                                  if (note.isStarred)
                                    const Chip(label: Text('مميزة')),
                                  if (note.isArchived)
                                    const Chip(label: Text('مؤرشفة')),
                                ],
                              ),
                            ],
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              final updated = value == 'star'
                                  ? note.copyWith(isStarred: !note.isStarred)
                                  : value == 'complete'
                                      ? note.copyWith(
                                          isCompleted: !note.isCompleted,
                                        )
                                      : note.copyWith(
                                          isArchived: !note.isArchived,
                                        );
                              if (value == 'edit') {
                                _editNote(note);
                              } else if (value == 'delete') {
                                _deleteNote(note);
                              } else {
                                _updateNote(updated);
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('تعديل'),
                              ),
                              PopupMenuItem(
                                value: 'star',
                                child: Text(
                                  note.isStarred ? 'إلغاء التمييز' : 'تمييز',
                                ),
                              ),
                              PopupMenuItem(
                                value: 'complete',
                                child: Text(
                                  note.isCompleted
                                      ? 'إعادة فتح المهمة'
                                      : 'إنهاء المهمة',
                                ),
                              ),
                              PopupMenuItem(
                                value: 'archive',
                                child: Text(
                                  note.isArchived ? 'إلغاء الأرشفة' : 'أرشفة',
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('حذف الملاحظة'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteDraft {
  const _NoteDraft({
    required this.title,
    required this.content,
    required this.type,
    required this.priority,
    required this.tags,
    required this.reminderAt,
    required this.reminderRepeat,
    required this.clearReminder,
  });

  final String title;
  final String content;
  final NoteType type;
  final NotePriority priority;
  final List<String> tags;
  final DateTime? reminderAt;
  final ReminderRepeatType reminderRepeat;
  final bool clearReminder;
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({this.note});

  final Note? note;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final TextEditingController _tagsController;
  late NoteType _type;
  late NotePriority _priority;
  DateTime? _reminderAt;
  ReminderRepeatType _repeat = ReminderRepeatType.none;

  @override
  void initState() {
    super.initState();
    final note = widget.note;
    _titleController = TextEditingController(text: note?.title ?? '');
    _contentController = TextEditingController(text: note?.content ?? '');
    _tagsController = TextEditingController(text: note?.tags.join(', ') ?? '');
    _type = note?.type ?? NoteType.general;
    _priority = note?.priority ?? NotePriority.medium;
    _reminderAt = note?.reminderAt?.toLocal();
    _repeat = note?.reminderRepeat ?? ReminderRepeatType.none;
  }

  Future<void> _pickReminder() async {
    final now = DateTime.now();
    final initial = _reminderAt ?? now.add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (!mounted || date == null) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted || time == null) {
      return;
    }
    setState(() {
      _reminderAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      return;
    }
    final tags = _tagsController.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
    Navigator.of(context).pop(
      _NoteDraft(
        title: title,
        content: _contentController.text.trim(),
        type: _type,
        priority: _priority,
        tags: tags,
        reminderAt: _reminderAt?.toUtc(),
        reminderRepeat:
            _reminderAt == null ? ReminderRepeatType.none : _repeat,
        clearReminder: _reminderAt == null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.note == null ? 'ملاحظة جديدة' : 'تعديل الملاحظة'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'العنوان'),
            ),
            TextField(
              controller: _contentController,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'المحتوى'),
            ),
            DropdownButtonFormField<NoteType>(
              value: _type,
              decoration: const InputDecoration(labelText: 'النوع'),
              items: NoteType.values
                  .map(
                    (type) => DropdownMenuItem(
                      value: type,
                      child: Text(type.arabicLabel),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _type = value);
                }
              },
            ),
            DropdownButtonFormField<NotePriority>(
              value: _priority,
              decoration: const InputDecoration(labelText: 'الأولوية'),
              items: NotePriority.values
                  .map(
                    (priority) => DropdownMenuItem(
                      value: priority,
                      child: Text(priority.arabicLabel),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _priority = value);
                }
              },
            ),
            TextField(
              controller: _tagsController,
              decoration: const InputDecoration(
                labelText: 'وسوم مفصولة بفاصلة',
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_note_outlined),
              title: const Text('موعد المتابعة (اختياري)'),
              subtitle: Text(
                _reminderAt == null
                    ? 'لا يوجد موعد. لا يتم إرسال إشعار تلقائي.'
                    : '${MaterialLocalizations.of(context).formatMediumDate(_reminderAt!)} '
                        '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(_reminderAt!))}',
              ),
              onTap: _pickReminder,
              trailing: _reminderAt == null
                  ? const Icon(Icons.edit_calendar_outlined)
                  : IconButton(
                      tooltip: 'إزالة الموعد',
                      onPressed: () => setState(() {
                        _reminderAt = null;
                        _repeat = ReminderRepeatType.none;
                      }),
                      icon: const Icon(Icons.clear),
                    ),
            ),
            if (_reminderAt != null)
              DropdownButtonFormField<ReminderRepeatType>(
                value: _repeat,
                decoration: const InputDecoration(labelText: 'تكرار التذكير'),
                items: ReminderRepeatType.values
                    .map(
                      (repeat) => DropdownMenuItem(
                        value: repeat,
                        child: Text(repeat.arabicLabel),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _repeat = value);
                  }
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
