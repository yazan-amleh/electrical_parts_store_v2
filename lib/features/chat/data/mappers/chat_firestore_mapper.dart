import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_participant.dart';
import '../../domain/entities/chat_room.dart';
import '../../domain/enums/chat_enums.dart';

abstract final class ChatFirestoreMapper {
  static ChatRoom roomFromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final createdAt = _date(data['createdAt'], DateTime.now().toUtc());
    return ChatRoom(
      id: snapshot.id,
      storeId: _string(data['storeId'], ''),
      name: _string(data['name'], 'محادثة'),
      participantIds: _stringList(data['participantIds']),
      participants: _participants(data['participants']),
      createdAt: createdAt,
      lastMessageAt: _optionalDate(data['lastMessageAt']),
      lastMessageText: _string(data['lastMessageText'], ''),
      lastMessageSenderId: _string(data['lastMessageSenderId'], ''),
      unreadCountByUser: _intMap(data['unreadCountByUser']),
      isGroup: data['isGroup'] is bool ? data['isGroup'] as bool : false,
      groupDescription: data['groupDescription'] as String?,
      createdBy: _string(data['createdBy'], ''),
      type: _roomType(data['type']),
      isArchived: data['isArchived'] is bool ? data['isArchived'] as bool : false,
    );
  }

  static ChatMessage messageFromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return ChatMessage(
      id: snapshot.id,
      roomId: _string(data['roomId'], ''),
      storeId: _string(data['storeId'], ''),
      senderId: _string(data['senderId'], ''),
      senderName: _string(data['senderName'], 'مستخدم'),
      senderPhotoUrl: data['senderPhotoUrl'] as String?,
      content: _string(data['content'], ''),
      sentAt: _date(data['sentAt'], DateTime.now().toUtc()),
      type: _messageType(data['type']),
      attachmentUrls: _stringList(data['attachmentUrls']),
      isDeleted: data['isDeleted'] is bool ? data['isDeleted'] as bool : false,
    );
  }

  static Map<String, dynamic> roomToMap(ChatRoom room) {
    return <String, dynamic>{
      'storeId': room.storeId,
      'name': room.name,
      'participantIds': room.participantIds,
      'participants': room.participants.map(_participantToMap).toList(),
      'createdAt': Timestamp.fromDate(room.createdAt),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastMessageAt': room.lastMessageAt == null
          ? null
          : Timestamp.fromDate(room.lastMessageAt!),
      'lastMessageText': room.lastMessageText,
      'lastMessageSenderId': room.lastMessageSenderId,
      'unreadCountByUser': room.unreadCountByUser,
      'isGroup': room.isGroup,
      'groupDescription': room.groupDescription,
      'createdBy': room.createdBy,
      'type': room.type.name,
      'isArchived': room.isArchived,
    };
  }

  static Map<String, dynamic> messageToMap(ChatMessage message) {
    return <String, dynamic>{
      'roomId': message.roomId,
      'storeId': message.storeId,
      'senderId': message.senderId,
      'senderName': message.senderName,
      'senderPhotoUrl': message.senderPhotoUrl,
      'content': message.content,
      'sentAt': Timestamp.fromDate(message.sentAt),
      'type': message.type.name,
      'attachmentUrls': message.attachmentUrls,
      'isDeleted': message.isDeleted,
    };
  }

  static Map<String, dynamic> _participantToMap(ChatParticipant participant) {
    return <String, dynamic>{
      'userId': participant.userId,
      'displayName': participant.displayName,
      'joinedAt': Timestamp.fromDate(participant.joinedAt),
      'isAdmin': participant.isAdmin,
      'photoUrl': participant.photoUrl,
    };
  }

  static List<ChatParticipant> _participants(Object? value) {
    if (value is! List) {
      return const <ChatParticipant>[];
    }
    return value
        .whereType<Map>()
        .map(
          (value) => ChatParticipant(
            userId: _string(value['userId'], ''),
            displayName: value['displayName'] as String?,
            joinedAt: _date(value['joinedAt'], DateTime.now().toUtc()),
            isAdmin: value['isAdmin'] is bool ? value['isAdmin'] as bool : false,
            photoUrl: value['photoUrl'] as String?,
          ),
        )
        .toList();
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) {
      return const <String>[];
    }
    return value.whereType<String>().toList();
  }

  static Map<String, int> _intMap(Object? value) {
    if (value is! Map) {
      return const <String, int>{};
    }
    final result = <String, int>{};
    value.forEach((key, value) {
      if (key is String && value is num) {
        result[key] = value.toInt();
      }
    });
    return result;
  }

  static DateTime? _optionalDate(Object? value) {
    if (value == null) {
      return null;
    }
    return _date(value, DateTime.now().toUtc());
  }

  static DateTime _date(Object? value, DateTime fallback) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  static String _string(Object? value, String fallback) {
    return value is String && value.trim().isNotEmpty ? value : fallback;
  }

  static ChatRoomType _roomType(Object? value) {
    return ChatRoomType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => ChatRoomType.direct,
    );
  }

  static ChatMessageType _messageType(Object? value) {
    return ChatMessageType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => ChatMessageType.text,
    );
  }
}
