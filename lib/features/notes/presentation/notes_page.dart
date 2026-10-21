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

class _NotesPageState extends State<NotesPage> {
  late final StoreContext _context;
  late Future<Result<List<Note>>> _notesFuture;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _includeArchived = false;

  @override
  void initState() {
    super.initState();
    _context = StoreContext(
      storeId: widget.membership.storeId,
      userId: widget.user.id,
    );
    _notesFuture = _loadNotes();
    _searchController.addListener(() {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text.trim().toLowerCase();
        });
      }
    });
  }

  Future<Result<List<Note>>> _loadNotes() {
    return widget.repository.getNotes(
      context: _context,
      includeArchived: _includeArchived,
    );
  }

  void _reload() {
    setState(() {
      _notesFuture = _loadNotes();
    });
  }

  Future<void> _editNote([Note? note]) async {
    final draft = await showDialog<_NoteDraft>(
      context: context,
      builder: (context) => _NoteDialog(note: note),
    );
    if (draft == null || !mounted) {
      return;
    }

    final now = DateTime.now().toUtc();
    final candidate = note == null
        ? Note(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            storeId: _context.storeId,
            userId: _context.userId,
            title: draft.title,
            content: draft.content,
            type: draft.type,
            priority: draft.priority,
            createdAt: now,
            tags: draft.tags,
          )
        : note.copyWith(
            title: draft.title,
            content: draft.content,
            type: draft.type,
            priority: draft.priority,
            tags: draft.tags,
            updatedAt: now,
          );

    final result = await widget.repository.saveNote(
      context: _context,
      note: candidate,
    );
    if (!mounted) {
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
    final result = await widget.repository.saveNote(
      context: _context,
      note: updated,
    );
    if (!mounted) {
      return;
    }
    if (result is FailureResult<void>) {
      _showMessage(result.failure.message);
    } else {
      _reload();
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  List<Note> _visibleNotes(List<Note> notes) {
    if (_searchQuery.isEmpty) {
      return notes;
    }
    return notes
        .where(
          (note) =>
              note.title.toLowerCase().contains(_searchQuery) ||
              note.content.toLowerCase().contains(_searchQuery) ||
              note.tags.any((tag) => tag.toLowerCase().contains(_searchQuery)),
        )
        .toList();
  }

  @override
  void dispose() {
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  FilterChip(
                    selected: !_includeArchived,
                    label: const Text('الحالية'),
                    onSelected: (selected) {
                      if (!selected) {
                        return;
                      }
                      setState(() {
                        _includeArchived = false;
                        _notesFuture = _loadNotes();
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    selected: _includeArchived,
                    label: const Text('مع المؤرشفة'),
                    onSelected: (selected) {
                      if (!selected) {
                        return;
                      }
                      setState(() {
                        _includeArchived = true;
                        _notesFuture = _loadNotes();
                      });
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<Result<List<Note>>>(
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
                          onTap: () => _editNote(note),
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
  });

  final String title;
  final String content;
  final NoteType type;
  final NotePriority priority;
  final List<String> tags;
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

  @override
  void initState() {
    super.initState();
    final note = widget.note;
    _titleController = TextEditingController(text: note?.title ?? '');
    _contentController = TextEditingController(text: note?.content ?? '');
    _tagsController = TextEditingController(text: note?.tags.join(', ') ?? '');
    _type = note?.type ?? NoteType.general;
    _priority = note?.priority ?? NotePriority.medium;
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
