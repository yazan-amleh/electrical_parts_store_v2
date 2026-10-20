import 'package:flutter/material.dart';

import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../../settings/domain/entities/store_member.dart';
import '../../settings/domain/repositories/settings_repository.dart';
import '../domain/entities/chat_attachment.dart';
import '../domain/entities/chat_message.dart';
import '../domain/entities/chat_participant.dart';
import '../domain/entities/chat_room.dart';
import '../domain/enums/chat_enums.dart';
import '../domain/repositories/chat_attachment_repository.dart';
import '../domain/repositories/chat_repository.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    required this.repository,
    this.attachmentRepository,
    required this.settingsRepository,
    required this.user,
    required this.membership,
    super.key,
  });

  final ChatRepository repository;
  final ChatAttachmentRepository? attachmentRepository;
  final SettingsRepository settingsRepository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final StoreContext _context;
  late final Stream<Result<List<ChatRoom>>> _rooms;
  List<StoreMember> _members = const [];
  bool _loadingMembers = true;
  String? _membersError;

  @override
  void initState() {
    super.initState();
    _context = StoreContext(
      storeId: widget.membership.storeId,
      userId: widget.user.id,
    );
    _rooms = widget.repository.watchRooms(context: _context);
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final result = await widget.settingsRepository.getMembers(
      context: _context,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _loadingMembers = false;
      if (result is Success<List<StoreMember>>) {
        _members = result.value
            .where(
                (member) => member.isActive && member.userId != widget.user.id)
            .toList();
        _membersError = null;
      } else if (result is FailureResult<List<StoreMember>>) {
        _membersError = result.failure.message;
      }
    });
  }

  Future<void> _createRoom() async {
    if (_loadingMembers) {
      return;
    }
    if (_membersError != null) {
      _showMessage(_membersError!);
      return;
    }

    final draft = await showDialog<_ChatRoomDraft>(
      context: context,
      builder: (context) => _CreateChatRoomDialog(members: _members),
    );
    if (draft == null || !mounted) {
      return;
    }

    final currentParticipant = ChatParticipant(
      userId: widget.user.id,
      displayName: widget.user.displayName ?? widget.user.email,
      joinedAt: DateTime.now().toUtc(),
      isAdmin: true,
    );
    final participants = <ChatParticipant>[
      currentParticipant,
      for (final member in _members)
        if (draft.selectedUserIds.contains(member.userId))
          ChatParticipant(
            userId: member.userId,
            displayName: _memberName(member),
            joinedAt: DateTime.now().toUtc(),
          ),
    ];

    final result = await widget.repository.createRoom(
      context: _context,
      name: draft.name,
      participants: participants,
      type: draft.type,
      groupDescription: draft.description,
    );
    if (!mounted) {
      return;
    }
    if (result is FailureResult<ChatRoom>) {
      _showMessage(result.failure.message);
    }
  }

  String _memberName(StoreMember member) {
    final displayName = member.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }
    final email = member.email?.trim();
    if (email != null && email.isNotEmpty) {
      return email;
    }
    return member.userId;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: StreamBuilder<Result<List<ChatRoom>>>(
          stream: _rooms,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ChatErrorState(message: snapshot.error.toString());
            }
            final result = snapshot.data;
            if (result is FailureResult<List<ChatRoom>>) {
              return _ChatErrorState(message: result.failure.message);
            }
            final rooms = result is Success<List<ChatRoom>>
                ? result.value
                : const <ChatRoom>[];
            if (rooms.isEmpty) {
              return _EmptyChatState(onCreate: _createRoom);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rooms.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final room = rooms[index];
                return _ChatRoomTile(
                  room: room,
                  userId: widget.user.id,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => ChatRoomPage(
                          repository: widget.repository,
                          attachmentRepository: widget.attachmentRepository,
                          room: room,
                          user: widget.user,
                          membership: widget.membership,
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _createRoom,
          icon: const Icon(Icons.add_comment_outlined),
          label: const Text('محادثة جديدة'),
        ),
      ),
    );
  }
}

class ChatRoomPage extends StatefulWidget {
  const ChatRoomPage({
    required this.repository,
    this.attachmentRepository,
    required this.room,
    required this.user,
    required this.membership,
    super.key,
  });

  final ChatRepository repository;
  final ChatAttachmentRepository? attachmentRepository;
  final ChatRoom room;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  late final StoreContext _context;
  late final Stream<Result<List<ChatMessage>>> _messages;
  final _composerController = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _context = StoreContext(
      storeId: widget.membership.storeId,
      userId: widget.user.id,
    );
    _messages = widget.repository.watchMessages(
      context: _context,
      roomId: widget.room.id,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
  }

  Future<void> _markRead() async {
    await widget.repository.markRoomRead(
      context: _context,
      roomId: widget.room.id,
    );
  }

  Future<void> _sendMessage() async {
    if (_sending) {
      return;
    }
    final content = _composerController.text.trim();
    if (content.isEmpty) {
      return;
    }
    setState(() {
      _sending = true;
    });
    final result = await widget.repository.sendMessage(
      context: _context,
      roomId: widget.room.id,
      senderName: widget.user.displayName ?? widget.user.email,
      content: content,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _sending = false;
    });
    if (result is Success<ChatMessage>) {
      _composerController.clear();
      return;
    }
    if (result is FailureResult<ChatMessage>) {
      _showMessage(result.failure.message);
    }
  }

  Future<void> _archiveRoom() async {
    final result = await widget.repository.archiveRoom(
      context: _context,
      roomId: widget.room.id,
    );
    if (!mounted) {
      return;
    }
    if (result is FailureResult<void>) {
      _showMessage(result.failure.message);
      return;
    }
    Navigator.of(context).pop();
  }

  void _showRoomInfo() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              shrinkWrap: true,
              children: [
                Text(
                  widget.room.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (widget.room.groupDescription?.trim().isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(widget.room.groupDescription!),
                  ),
                const SizedBox(height: 16),
                Text(
                  'المشاركون',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final participant in widget.room.participants)
                  ListTile(
                    dense: true,
                    leading: const CircleAvatar(
                      child: Icon(Icons.person_outline),
                    ),
                    title: Text(
                      participant.displayName?.trim().isNotEmpty == true
                          ? participant.displayName!
                          : participant.userId,
                    ),
                    trailing: participant.isAdmin
                        ? const Chip(label: Text('مشرف'))
                        : null,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.room.name),
          actions: [
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'info') {
                  _showRoomInfo();
                } else if (value == 'archive') {
                  _archiveRoom();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem<String>(
                  value: 'info',
                  child: Text('معلومات المحادثة'),
                ),
                PopupMenuItem<String>(
                  value: 'archive',
                  child: Text('أرشفة المحادثة'),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: StreamBuilder<Result<List<ChatMessage>>>(
                stream: _messages,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _ChatErrorState(message: snapshot.error.toString());
                  }
                  final result = snapshot.data;
                  if (result is FailureResult<List<ChatMessage>>) {
                    return _ChatErrorState(message: result.failure.message);
                  }
                  final messages = result is Success<List<ChatMessage>>
                      ? result.value
                      : const <ChatMessage>[];
                  if (messages.isEmpty) {
                    return const Center(child: Text('لا توجد رسائل بعد.'));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      return _MessageBubble(
                        message: message,
                        isMine: message.senderId == widget.user.id,
                      );
                    },
                  );
                },
              ),
            ),
            _MessageComposer(
              controller: _composerController,
              sending: _sending,
              onSend: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _composerController.dispose();
    super.dispose();
  }
}

class _ChatRoomTile extends StatelessWidget {
  const _ChatRoomTile({
    required this.room,
    required this.userId,
    required this.onTap,
  });

  final ChatRoom room;
  final String userId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = room.unreadCountFor(userId);
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          child: Icon(
            room.isGroup ? Icons.groups_outlined : Icons.person_outline,
          ),
        ),
        title: Text(room.name),
        subtitle: Text(
          room.lastMessageText.isEmpty ? 'ابدأ المحادثة' : room.lastMessageText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: unread == 0
            ? null
            : CircleAvatar(
                radius: 12,
                child: Text(
                  unread > 99 ? '99+' : unread.toString(),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
      ),
    );
  }
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: 'اكتب رسالة...',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: sending ? null : onSend,
                icon: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                tooltip: 'إرسال',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
  });

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    if (message.type == ChatMessageType.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Text(
            message.content,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: isMine
          ? AlignmentDirectional.centerStart
          : AlignmentDirectional.centerEnd,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Card(
          color:
              isMine ? colors.primaryContainer : colors.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isMine)
                  Text(
                    message.senderName,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                if (!isMine) const SizedBox(height: 4),
                if (message.content.isNotEmpty) Text(message.content),
                if (message.attachmentUrls.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('مرفق'),
                  ),
                const SizedBox(height: 4),
                Text(
                  TimeOfDay.fromDateTime(message.sentAt.toLocal())
                      .format(context),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyChatState extends StatelessWidget {
  const _EmptyChatState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.forum_outlined, size: 56),
            const SizedBox(height: 16),
            const Text('لا توجد محادثات في هذا المتجر.'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('إنشاء محادثة'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatErrorState extends StatelessWidget {
  const _ChatErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

class _ChatRoomDraft {
  const _ChatRoomDraft({
    required this.name,
    required this.type,
    required this.selectedUserIds,
    this.description,
  });

  final String name;
  final ChatRoomType type;
  final Set<String> selectedUserIds;
  final String? description;
}

class _CreateChatRoomDialog extends StatefulWidget {
  const _CreateChatRoomDialog({required this.members});

  final List<StoreMember> members;

  @override
  State<_CreateChatRoomDialog> createState() => _CreateChatRoomDialogState();
}

class _CreateChatRoomDialogState extends State<_CreateChatRoomDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _selectedUserIds = <String>{};
  ChatRoomType _type = ChatRoomType.group;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('محادثة جديدة'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<ChatRoomType>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'النوع'),
                items: const [
                  DropdownMenuItem(
                    value: ChatRoomType.direct,
                    child: Text('مباشرة'),
                  ),
                  DropdownMenuItem(
                    value: ChatRoomType.group,
                    child: Text('مجموعة'),
                  ),
                  DropdownMenuItem(
                    value: ChatRoomType.support,
                    child: Text('دعم'),
                  ),
                  DropdownMenuItem(
                    value: ChatRoomType.announcement,
                    child: Text('إعلان'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _type = value;
                    if (_type == ChatRoomType.direct &&
                        _selectedUserIds.length > 1) {
                      _selectedUserIds.removeWhere(
                        (userId) => userId != _selectedUserIds.first,
                      );
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'اسم المحادثة'),
              ),
              if (_type != ChatRoomType.direct) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(labelText: 'الوصف'),
                  maxLines: 2,
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'اختيار المشاركين',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              if (widget.members.isEmpty)
                const Text('لا يوجد أعضاء نشطون آخرون.'),
              for (final member in widget.members)
                CheckboxListTile(
                  value: _selectedUserIds.contains(member.userId),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(_memberName(member)),
                  subtitle: member.email == null ? null : Text(member.email!),
                  onChanged: (selected) {
                    setState(() {
                      if (_type == ChatRoomType.direct) {
                        _selectedUserIds
                          ..clear()
                          ..add(member.userId);
                      } else if (selected == true) {
                        _selectedUserIds.add(member.userId);
                      } else {
                        _selectedUserIds.remove(member.userId);
                      }
                    });
                  },
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('إنشاء'),
        ),
      ],
    );
  }

  String _memberName(StoreMember member) {
    final displayName = member.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }
    final email = member.email?.trim();
    if (email != null && email.isNotEmpty) {
      return email;
    }
    return member.userId;
  }

  void _submit() {
    if (_selectedUserIds.isEmpty) {
      return;
    }
    var name = _nameController.text.trim();
    if (name.isEmpty && _type == ChatRoomType.direct) {
      final selected = widget.members.firstWhere(
        (member) => _selectedUserIds.contains(member.userId),
      );
      name = _memberName(selected);
    }
    if (name.isEmpty) {
      return;
    }
    Navigator.of(context).pop(
      _ChatRoomDraft(
        name: name,
        type: _type,
        selectedUserIds: Set.unmodifiable(_selectedUserIds),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}
