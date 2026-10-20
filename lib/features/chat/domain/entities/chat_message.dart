import '../enums/chat_enums.dart';

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.roomId,
    required this.storeId,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.sentAt,
    this.senderPhotoUrl,
    this.type = ChatMessageType.text,
    List<String>? attachmentUrls,
    this.isDeleted = false,
  }) : attachmentUrls = List.unmodifiable(attachmentUrls ?? const <String>[]) {
    if (id.trim().isEmpty ||
        roomId.trim().isEmpty ||
        storeId.trim().isEmpty ||
        senderId.trim().isEmpty) {
      throw ArgumentError('Chat message identity fields are required.');
    }
    if (id.contains('/') || roomId.contains('/') || storeId.contains('/')) {
      throw ArgumentError('Chat message identifiers cannot contain a slash.');
    }
    if (content.trim().isEmpty && this.attachmentUrls.isEmpty) {
      throw ArgumentError('Chat messages require content or an attachment.');
    }
  }

  final String id;
  final String roomId;
  final String storeId;
  final String senderId;
  final String senderName;
  final String? senderPhotoUrl;
  final String content;
  final DateTime sentAt;
  final ChatMessageType type;
  final List<String> attachmentUrls;
  final bool isDeleted;
}
