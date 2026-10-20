import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/features/chat/domain/entities/chat_message.dart';
import 'package:electrical_parts_store_v2/features/chat/domain/entities/chat_participant.dart';
import 'package:electrical_parts_store_v2/features/chat/domain/entities/chat_room.dart';

void main() {
  final joinedAt = DateTime.utc(2026, 1, 1);

  test('room keeps unread counts isolated per participant', () {
    final room = ChatRoom(
      id: 'room-1',
      storeId: 'store-1',
      name: 'الفريق',
      participantIds: const ['user-1', 'user-2'],
      participants: [
        ChatParticipant(
          userId: 'user-1',
          displayName: 'الأول',
          joinedAt: joinedAt,
        ),
        ChatParticipant(
          userId: 'user-2',
          displayName: 'الثاني',
          joinedAt: joinedAt,
        ),
      ],
      createdAt: joinedAt,
      createdBy: 'user-1',
      unreadCountByUser: const {'user-1': 0, 'user-2': 3},
    );

    expect(room.unreadCountFor('user-1'), 0);
    expect(room.unreadCountFor('user-2'), 3);
    expect(room.unreadCountFor('missing'), 0);
  });

  test('message accepts attachment-only payloads', () {
    final message = ChatMessage(
      id: 'message-1',
      roomId: 'room-1',
      storeId: 'store-1',
      senderId: 'user-1',
      senderName: 'الأول',
      content: '',
      sentAt: joinedAt,
      attachmentUrls: const ['https://example.com/file'],
    );

    expect(message.attachmentUrls, hasLength(1));
  });

  test('message rejects an empty payload', () {
    expect(
      () => ChatMessage(
        id: 'message-1',
        roomId: 'room-1',
        storeId: 'store-1',
        senderId: 'user-1',
        senderName: 'الأول',
        content: '',
        sentAt: joinedAt,
      ),
      throwsArgumentError,
    );
  });
}
