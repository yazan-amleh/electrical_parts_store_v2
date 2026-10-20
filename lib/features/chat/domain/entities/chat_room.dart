import 'chat_enums.dart';
import 'chat_participant.dart';

class ChatRoom {
  ChatRoom({
    required this.id,
    required this.storeId,
    required this.name,
    required List<String> participantIds,
    required List<ChatParticipant> participants,
    required this.createdAt,
    required this.createdBy,
    this.lastMessageAt,
    this.lastMessageText = '',
    this.lastMessageSenderId = '',
    Map<String, int>? unreadCountByUser,
    this.isGroup = false,
    this.groupDescription,
    this.type = ChatRoomType.direct,
    this.isArchived = false,
  })  : participantIds = List.unmodifiable(participantIds),
        participants = List.unmodifiable(participants),
        unreadCountByUser = Map.unmodifiable(
          unreadCountByUser ?? const <String, int>{},
        ) {
    if (id.trim().isEmpty ||
        storeId.trim().isEmpty ||
        name.trim().isEmpty ||
        createdBy.trim().isEmpty) {
      throw ArgumentError('Chat room identity fields are required.');
    }
    if (id.contains('/') || storeId.contains('/') || createdBy.contains('/')) {
      throw ArgumentError('Chat room identifiers cannot contain a slash.');
    }
    if (this.participantIds.isEmpty ||
        this.participantIds.length != this.participantIds.toSet().length) {
      throw ArgumentError('Chat rooms require unique participants.');
    }
    if (this.participants.any(
      (participant) => !this.participantIds.contains(participant.userId),
    )) {
      throw ArgumentError('Chat participants must belong to the room.');
    }
  }

  final String id;
  final String storeId;
  final String name;
  final List<String> participantIds;
  final List<ChatParticipant> participants;
  final DateTime createdAt;
  final DateTime? lastMessageAt;
  final String lastMessageText;
  final String lastMessageSenderId;
  final Map<String, int> unreadCountByUser;
  final bool isGroup;
  final String? groupDescription;
  final String createdBy;
  final ChatRoomType type;
  final bool isArchived;

  int unreadCountFor(String userId) => unreadCountByUser[userId] ?? 0;

  ChatRoom copyWith({
    String? name,
    List<String>? participantIds,
    List<ChatParticipant>? participants,
    DateTime? createdAt,
    DateTime? lastMessageAt,
    String? lastMessageText,
    String? lastMessageSenderId,
    Map<String, int>? unreadCountByUser,
    bool? isGroup,
    String? groupDescription,
    String? createdBy,
    ChatRoomType? type,
    bool? isArchived,
  }) {
    return ChatRoom(
      id: id,
      storeId: storeId,
      name: name ?? this.name,
      participantIds: participantIds ?? this.participantIds,
      participants: participants ?? this.participants,
      createdAt: createdAt ?? this.createdAt,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastMessageText: lastMessageText ?? this.lastMessageText,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      unreadCountByUser: unreadCountByUser ?? this.unreadCountByUser,
      isGroup: isGroup ?? this.isGroup,
      groupDescription: groupDescription ?? this.groupDescription,
      createdBy: createdBy ?? this.createdBy,
      type: type ?? this.type,
      isArchived: isArchived ?? this.isArchived,
    );
  }
}
