import 'package:flutter/material.dart';

import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/enums/store_role.dart';
import '../../settings/domain/entities/store_member.dart';
import '../domain/entities/chat_participant.dart';
import '../domain/entities/chat_room.dart';
import '../domain/repositories/chat_repository.dart';

/// Shows participants for everyone, but mutation controls only for authorized
/// creators and store managers. Firestore rules enforce the same restriction.
class ChatRoomDetailsSheet extends StatefulWidget {
  const ChatRoomDetailsSheet({
    required this.room,
    required this.contextForStore,
    required this.currentRole,
    required this.repository,
    required this.availableMembers,
    super.key,
  });

  final ChatRoom room;
  final StoreContext contextForStore;
  final StoreRole currentRole;
  final ChatRepository repository;
  final List<StoreMember> availableMembers;

  @override
  State<ChatRoomDetailsSheet> createState() => _ChatRoomDetailsSheetState();
}

class _ChatRoomDetailsSheetState extends State<ChatRoomDetailsSheet> {
  late ChatRoom _room;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _room = widget.room;
  }

  bool get _canManage {
    final role = widget.currentRole;
    return (_room.isGroup || _room.type.name == 'group') &&
        (_room.createdBy == widget.contextForStore.userId ||
            role == StoreRole.owner ||
            role == StoreRole.admin);
  }

  String _label(StoreMember member) {
    final name = member.displayName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    final email = member.email?.trim();
    if (email != null && email.isNotEmpty) {
      return email;
    }
    return member.userId;
  }

  void _error(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _updateGroup() async {
    final nameController = TextEditingController(text: _room.name);
    final descriptionController = TextEditingController(
      text: _room.groupDescription ?? '',
    );
    final details = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تعديل معلومات المجموعة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'اسم المجموعة'),
            ),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(labelText: 'الوصف'),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, [
              nameController.text.trim(),
              descriptionController.text.trim(),
            ]),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    nameController.dispose();
    descriptionController.dispose();
    if (!mounted || details == null || details.first.isEmpty) {
      return;
    }
    setState(() => _saving = true);
    final result = await widget.repository.updateRoom(
      context: widget.contextForStore,
      roomId: _room.id,
      name: details[0],
      groupDescription: details[1],
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
      if (result is Success<void>) {
        _room = _room.copyWith(
          name: details[0],
          groupDescription: details[1],
        );
      }
    });
    if (result is FailureResult<void>) {
      _error(result.failure.message);
    }
  }

  Future<void> _addParticipant() async {
    final choices = widget.availableMembers
        .where(
          (member) =>
              member.isActive && !_room.participantIds.contains(member.userId),
        )
        .toList();
    if (choices.isEmpty) {
      _error('لا يوجد أعضاء متاحون للإضافة أو لا تملك صلاحية عرضهم.');
      return;
    }
    final selected = await showDialog<StoreMember>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('إضافة مشارك'),
        children: [
          for (final member in choices)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, member),
              child: Text(_label(member)),
            ),
        ],
      ),
    );
    if (!mounted || selected == null) {
      return;
    }
    final participant = ChatParticipant(
      userId: selected.userId,
      displayName: _label(selected),
      joinedAt: DateTime.now().toUtc(),
    );
    setState(() => _saving = true);
    final result = await widget.repository.addParticipant(
      context: widget.contextForStore,
      roomId: _room.id,
      participant: participant,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
      if (result is Success<void>) {
        _room = _room.copyWith(
          participantIds: [..._room.participantIds, selected.userId],
          participants: [..._room.participants, participant],
        );
      }
    });
    if (result is FailureResult<void>) {
      _error(result.failure.message);
    }
  }

  Future<void> _removeParticipant(ChatParticipant participant) async {
    if (participant.userId == widget.contextForStore.userId ||
        participant.userId == _room.createdBy ||
        _room.participantIds.length <= 2) {
      _error('لا يمكن إزالة هذا المشارك من المجموعة.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إزالة مشارك'),
        content:
            Text('إزالة ${participant.displayName ?? participant.userId}؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('إزالة'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }
    setState(() => _saving = true);
    final result = await widget.repository.removeParticipant(
      context: widget.contextForStore,
      roomId: _room.id,
      userId: participant.userId,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
      if (result is Success<void>) {
        _room = _room.copyWith(
          participantIds: _room.participantIds
              .where((id) => id != participant.userId)
              .toList(),
          participants: _room.participants
              .where((entry) => entry.userId != participant.userId)
              .toList(),
        );
      }
    });
    if (result is FailureResult<void>) {
      _error(result.failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _room.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (_canManage)
                  IconButton(
                    tooltip: 'تعديل معلومات المجموعة',
                    onPressed: _saving ? null : _updateGroup,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                IconButton(
                  tooltip: 'إغلاق',
                  onPressed: () => Navigator.pop(context, _room),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (_room.groupDescription?.trim().isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_room.groupDescription!),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'المشاركون (${_room.participants.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (_canManage)
                  TextButton.icon(
                    onPressed: _saving ? null : _addParticipant,
                    icon: const Icon(Icons.person_add_outlined),
                    label: const Text('إضافة'),
                  ),
              ],
            ),
            for (final participant in _room.participants)
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.person_outline),
                ),
                title: Text(
                  participant.displayName?.trim().isNotEmpty == true
                      ? participant.displayName!
                      : participant.userId,
                ),
                trailing: _canManage &&
                        participant.userId != _room.createdBy &&
                        participant.userId != widget.contextForStore.userId &&
                        _room.participantIds.length > 2
                    ? IconButton(
                        tooltip: 'إزالة مشارك',
                        onPressed: _saving
                            ? null
                            : () => _removeParticipant(participant),
                        icon: const Icon(Icons.person_remove_outlined),
                      )
                    : participant.isAdmin
                        ? const Chip(label: Text('مشرف'))
                        : null,
              ),
            if (_saving) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
