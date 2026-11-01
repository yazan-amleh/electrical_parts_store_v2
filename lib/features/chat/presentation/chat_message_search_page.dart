import 'package:flutter/material.dart';

import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../domain/entities/chat_message.dart';
import '../domain/repositories/chat_repository.dart';

/// V1-style conversation search. Results are searched in the room's loaded
/// message stream, not across other rooms or other stores.
class ChatMessageSearchPage extends StatefulWidget {
  const ChatMessageSearchPage({
    required this.repository,
    required this.storeContext,
    required this.roomId,
    super.key,
  });

  final ChatRepository repository;
  final StoreContext storeContext;
  final String roomId;

  @override
  State<ChatMessageSearchPage> createState() => _ChatMessageSearchPageState();
}

class _ChatMessageSearchPageState extends State<ChatMessageSearchPage> {
  late Stream<Result<List<ChatMessage>>> _messages;
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    _messages = widget.repository.watchMessages(
      context: widget.storeContext,
      roomId: widget.roomId,
    );
  }

  @override
  void didUpdateWidget(covariant ChatMessageSearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.roomId != widget.roomId ||
        oldWidget.storeContext.storeId != widget.storeContext.storeId ||
        oldWidget.storeContext.userId != widget.storeContext.userId) {
      _search.clear();
      _query = '';
      _bind();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _showResult(ChatMessage message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(message.senderName),
        content: SelectableText(
            message.content.isEmpty ? 'رسالة تحتوي على مرفق' : message.content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('البحث في المحادثة')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: (value) {
                  setState(() => _query = value.trim().toLowerCase());
                },
                decoration: InputDecoration(
                  hintText: 'ابحث في رسائل المحادثة',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'مسح البحث',
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.clear),
                        ),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<Result<List<ChatMessage>>>(
                key: ValueKey(
                  '${widget.storeContext.storeId}/'
                  '${widget.storeContext.userId}/${widget.roomId}',
                ),
                stream: _messages,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text(snapshot.error.toString()));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final result = snapshot.data;
                  if (result is FailureResult<List<ChatMessage>>) {
                    return Center(child: Text(result.failure.message));
                  }
                  if (result is! Success<List<ChatMessage>>) {
                    return const SizedBox.shrink();
                  }
                  if (_query.isEmpty) {
                    return const Center(
                      child: Text('اكتب كلمة للبحث داخل هذه المحادثة.'),
                    );
                  }
                  final matches = result.value
                      .where(
                        (message) =>
                            message.storeId == widget.storeContext.storeId &&
                            message.roomId == widget.roomId &&
                            !message.isDeleted &&
                            (message.content.toLowerCase().contains(_query) ||
                                message.senderName
                                    .toLowerCase()
                                    .contains(_query)),
                      )
                      .toList()
                    ..sort((a, b) => b.sentAt.compareTo(a.sentAt));
                  if (matches.isEmpty) {
                    return const Center(child: Text('لا توجد نتائج مطابقة.'));
                  }
                  return ListView.builder(
                    itemCount: matches.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Text('النتائج: ${matches.length}'),
                        );
                      }
                      final message = matches[index - 1];
                      final local = message.sentAt.toLocal();
                      return ListTile(
                        leading: const Icon(Icons.chat_bubble_outline),
                        title: Text(message.senderName),
                        subtitle: Text(
                          message.content.isEmpty ? 'مرفق' : message.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          '${local.day}/${local.month}/${local.year}',
                        ),
                        onTap: () => _showResult(message),
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
