import 'package:flutter/material.dart';

import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../../categories/domain/repositories/category_repository.dart';
import '../../inventory/domain/repositories/product_repository.dart';
import '../../reports/domain/repositories/reports_repository.dart';
import '../application/store_assistant_service.dart';

class ChatbotPage extends StatefulWidget {
  const ChatbotPage({
    required this.productRepository,
    required this.categoryRepository,
    required this.reportsRepository,
    required this.user,
    required this.membership,
    super.key,
  });

  final ProductRepository productRepository;
  final CategoryRepository categoryRepository;
  final ReportsRepository reportsRepository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<ChatbotPage> createState() => _ChatbotPageState();
}

class _ChatbotPageState extends State<ChatbotPage> {
  late final StoreContext _context;
  late final StoreAssistantService _assistant;
  late final TextEditingController _controller;
  final List<_AssistantMessage> _messages = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _context = StoreContext(
      storeId: widget.membership.storeId,
      userId: widget.user.id,
    );
    _assistant = StoreAssistantService(
      productRepository: widget.productRepository,
      categoryRepository: widget.categoryRepository,
      reportsRepository: widget.reportsRepository,
    );
    _controller = TextEditingController();
    _messages.add(
      const _AssistantMessage(
        text: 'مرحباً. اسألني عن مبيعات اليوم، المخزون، أو التصنيفات.',
        isUser: false,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) {
      return;
    }
    _controller.clear();
    setState(() {
      _messages.add(_AssistantMessage(text: text, isUser: true));
      _loading = true;
    });
    final response = await _assistant.answer(
      context: _context,
      message: text,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _messages.add(_AssistantMessage(text: response, isUser: false));
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('المساعد الذكي')),
        body: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  return Align(
                    alignment: message.isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 520),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: message.isUser
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(message.text),
                    ),
                  );
                },
              ),
            ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText: 'اكتب سؤالك',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _loading ? null : _send,
                      icon: const Icon(Icons.send),
                      tooltip: 'إرسال',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistantMessage {
  const _AssistantMessage({
    required this.text,
    required this.isUser,
  });

  final String text;
  final bool isUser;
}
