import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../../infrastructure/firebase/firebase_paths.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_participant.dart';
import '../../domain/entities/chat_room.dart';
import '../../domain/enums/chat_enums.dart';
import '../../domain/repositories/chat_repository.dart';
import '../mappers/chat_firestore_mapper.dart';

class FirestoreChatRepository implements ChatRepository {
  FirestoreChatRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  @override
  Stream<Result<List<ChatRoom>>> watchRooms({
    required StoreContext context,
  }) async* {
    if (context.storeId.trim().isEmpty || context.userId.trim().isEmpty) {
      yield const FailureResult<List<ChatRoom>>(
        ValidationFailure('A store and user are required to read chat rooms.'),
      );
      return;
    }

    try {
      final query = FirebasePaths.chatRooms(
        _firestore,
        context.storeId,
      ).where('participantIds', arrayContains: context.userId);
      await for (final snapshot in query.snapshots()) {
        final rooms = snapshot.docs
            .map(ChatFirestoreMapper.roomFromSnapshot)
            .where(
              (room) => room.storeId == context.storeId && !room.isArchived,
            )
            .toList()
          ..sort(
            (left, right) => (right.lastMessageAt ?? right.createdAt).compareTo(
              left.lastMessageAt ?? left.createdAt,
            ),
          );
        yield Success<List<ChatRoom>>(rooms);
      }
    } on FirebaseException catch (error) {
      yield FailureResult<List<ChatRoom>>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      yield FailureResult<List<ChatRoom>>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Stream<Result<List<ChatMessage>>> watchMessages({
    required StoreContext context,
    required String roomId,
  }) async* {
    if (context.storeId.trim().isEmpty || context.userId.trim().isEmpty) {
      yield const FailureResult<List<ChatMessage>>(
        ValidationFailure('A store and user are required to read messages.'),
      );
      return;
    }
    if (roomId.trim().isEmpty || roomId.contains('/')) {
      yield const FailureResult<List<ChatMessage>>(
        ValidationFailure('The chat room id is invalid.'),
      );
      return;
    }

    try {
      final query = FirebasePaths.chatMessages(
        _firestore,
        context.storeId,
        roomId,
      ).orderBy('sentAt');
      await for (final snapshot in query.snapshots()) {
        final messages = snapshot.docs
            .map(ChatFirestoreMapper.messageFromSnapshot)
            .where(
              (message) =>
                  message.storeId == context.storeId &&
                  message.roomId == roomId,
            )
            .toList();
        yield Success<List<ChatMessage>>(messages);
      }
    } on FirebaseException catch (error) {
      yield FailureResult<List<ChatMessage>>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      yield FailureResult<List<ChatMessage>>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<ChatRoom>> createRoom({
    required StoreContext context,
    required String name,
    required List<ChatParticipant> participants,
    required ChatRoomType type,
    String? groupDescription,
  }) async {
    final normalizedName = name.trim();
    final ids = participants.map((participant) => participant.userId).toList();
    if (normalizedName.isEmpty || ids.isEmpty) {
      return const FailureResult<ChatRoom>(
        ValidationFailure('A chat room name and participants are required.'),
      );
    }
    if (!ids.contains(context.userId)) {
      return const FailureResult<ChatRoom>(
        AuthorizationFailure('The current user must join the chat room.'),
      );
    }
    if (ids.length != ids.toSet().length) {
      return const FailureResult<ChatRoom>(
        ValidationFailure('Chat room participants must be unique.'),
      );
    }

    try {
      final roomRef = FirebasePaths.chatRooms(
        _firestore,
        context.storeId,
      ).doc();
      final now = DateTime.now().toUtc();
      final room = ChatRoom(
        id: roomRef.id,
        storeId: context.storeId,
        name: normalizedName,
        participantIds: ids,
        participants: participants,
        createdAt: now,
        createdBy: context.userId,
        unreadCountByUser: <String, int>{
          for (final userId in ids) userId: 0,
        },
        isGroup: type != ChatRoomType.direct,
        groupDescription: groupDescription?.trim(),
        type: type,
      );
      await roomRef.set(ChatFirestoreMapper.roomToMap(room));
      return Success<ChatRoom>(room);
    } on FirebaseException catch (error) {
      return FailureResult<ChatRoom>(
        _mapFailure(error, 'The chat room could not be created.'),
      );
    } catch (error) {
      return FailureResult<ChatRoom>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<ChatMessage>> sendMessage({
    required StoreContext context,
    required String roomId,
    required String senderName,
    required String content,
    ChatMessageType type = ChatMessageType.text,
    List<String> attachmentUrls = const [],
  }) async {
    final normalizedContent = content.trim();
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty || normalizedRoomId.contains('/')) {
      return const FailureResult<ChatMessage>(
        ValidationFailure('The chat room id is invalid.'),
      );
    }
    if (normalizedContent.isEmpty && attachmentUrls.isEmpty) {
      return const FailureResult<ChatMessage>(
        ValidationFailure('A message requires text or an attachment.'),
      );
    }

    try {
      final roomRef = FirebasePaths.chatRoom(
        _firestore,
        context.storeId,
        normalizedRoomId,
      );
      final message = await _firestore.runTransaction<ChatMessage>(
        (transaction) async {
          final roomSnapshot = await transaction.get(roomRef);
          if (!roomSnapshot.exists) {
            throw FirebaseException(
              plugin: 'cloud_firestore',
              code: 'not-found',
              message: 'The chat room was not found.',
            );
          }
          final roomData = roomSnapshot.data() ?? const <String, dynamic>{};
          final participantIds = _stringList(roomData['participantIds']);
          if (!participantIds.contains(context.userId)) {
            throw FirebaseException(
              plugin: 'cloud_firestore',
              code: 'permission-denied',
              message: 'The user is not a chat participant.',
            );
          }
          if (roomData['isArchived'] == true) {
            throw FirebaseException(
              plugin: 'cloud_firestore',
              code: 'failed-precondition',
              message: 'The chat room is archived.',
            );
          }

          final now = DateTime.now().toUtc();
          final messageRef = roomRef.collection('messages').doc();
          final unread = _intMap(roomData['unreadCountByUser']);
          for (final participantId in participantIds) {
            if (participantId != context.userId) {
              unread[participantId] = (unread[participantId] ?? 0) + 1;
            }
          }
          final value = ChatMessage(
            id: messageRef.id,
            roomId: normalizedRoomId,
            storeId: context.storeId,
            senderId: context.userId,
            senderName:
                senderName.trim().isEmpty ? 'مستخدم' : senderName.trim(),
            content: normalizedContent,
            sentAt: now,
            type: type,
            attachmentUrls: attachmentUrls,
          );
          transaction.set(messageRef, ChatFirestoreMapper.messageToMap(value));
          transaction.update(roomRef, <String, dynamic>{
            'lastMessageAt': Timestamp.fromDate(now),
            'lastMessageText': normalizedContent,
            'lastMessageSenderId': context.userId,
            'unreadCountByUser': unread,
            'updatedAt': Timestamp.fromDate(now),
          });
          return value;
        },
      );
      return Success<ChatMessage>(message);
    } on FirebaseException catch (error) {
      return FailureResult<ChatMessage>(
        _mapFailure(error, 'The message could not be sent.'),
      );
    } catch (error) {
      return FailureResult<ChatMessage>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<void>> markRoomRead({
    required StoreContext context,
    required String roomId,
  }) async {
    return _updateRoomUnreadCount(
      context: context,
      roomId: roomId,
      count: 0,
    );
  }

  @override
  Future<Result<void>> updateRoom({
    required StoreContext context,
    required String roomId,
    String? name,
    String? groupDescription,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null && name.trim().isNotEmpty) {
      updates['name'] = name.trim();
    }
    if (groupDescription != null) {
      updates['groupDescription'] = groupDescription.trim();
    }
    if (updates.isEmpty) {
      return const FailureResult<void>(
        ValidationFailure('There are no room changes to apply.'),
      );
    }
    return _updateRoomFields(
      context: context,
      roomId: roomId,
      updates: updates,
    );
  }

  @override
  Future<Result<void>> addParticipant({
    required StoreContext context,
    required String roomId,
    required ChatParticipant participant,
  }) async {
    return _changeParticipants(
      context: context,
      roomId: roomId,
      mutate: (room) {
        if (room.participantIds.contains(participant.userId)) {
          return room;
        }
        return room.copyWith(
          participantIds: [...room.participantIds, participant.userId],
          participants: [...room.participants, participant],
          unreadCountByUser: <String, int>{
            ...room.unreadCountByUser,
            participant.userId: 0,
          },
        );
      },
    );
  }

  @override
  Future<Result<void>> removeParticipant({
    required StoreContext context,
    required String roomId,
    required String userId,
  }) async {
    if (userId == context.userId) {
      return const FailureResult<void>(
        ValidationFailure('The current user cannot remove themselves here.'),
      );
    }
    return _changeParticipants(
      context: context,
      roomId: roomId,
      mutate: (room) {
        final ids = room.participantIds.where((id) => id != userId).toList();
        final participants = room.participants
            .where((participant) => participant.userId != userId)
            .toList();
        final unread = <String, int>{...room.unreadCountByUser}..remove(userId);
        if (ids.isEmpty) {
          return room;
        }
        return room.copyWith(
          participantIds: ids,
          participants: participants,
          unreadCountByUser: unread,
        );
      },
    );
  }

  @override
  Future<Result<void>> archiveRoom({
    required StoreContext context,
    required String roomId,
  }) async {
    return _updateRoomFields(
      context: context,
      roomId: roomId,
      updates: <String, dynamic>{'isArchived': true},
    );
  }

  Future<Result<void>> _updateRoomUnreadCount({
    required StoreContext context,
    required String roomId,
    required int count,
  }) async {
    return _updateRoomFields(
      context: context,
      roomId: roomId,
      updates: <String, dynamic>{
        'unreadCountByUser.${context.userId}': count,
      },
    );
  }

  Future<Result<void>> _updateRoomFields({
    required StoreContext context,
    required String roomId,
    required Map<String, dynamic> updates,
  }) async {
    if (roomId.trim().isEmpty || roomId.contains('/')) {
      return const FailureResult<void>(
        ValidationFailure('The chat room id is invalid.'),
      );
    }
    try {
      await FirebasePaths.chatRoom(
        _firestore,
        context.storeId,
        roomId.trim(),
      ).update({
        ...updates,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return const Success<void>(null);
    } on FirebaseException catch (error) {
      return FailureResult<void>(
        _mapFailure(error, 'The chat room could not be updated.'),
      );
    } catch (error) {
      return FailureResult<void>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  Future<Result<void>> _changeParticipants({
    required StoreContext context,
    required String roomId,
    required ChatRoom Function(ChatRoom room) mutate,
  }) async {
    try {
      final roomRef = FirebasePaths.chatRoom(
        _firestore,
        context.storeId,
        roomId,
      );
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(roomRef);
        if (!snapshot.exists) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'not-found',
            message: 'The chat room was not found.',
          );
        }
        final room = ChatFirestoreMapper.roomFromSnapshot(snapshot);
        final nextRoom = mutate(room);
        transaction.update(
          roomRef,
          <String, dynamic>{
            'participantIds': nextRoom.participantIds,
            'participants': nextRoom.participants
                .map(
                  (participant) => <String, dynamic>{
                    'userId': participant.userId,
                    'displayName': participant.displayName,
                    'joinedAt': Timestamp.fromDate(participant.joinedAt),
                    'isAdmin': participant.isAdmin,
                    'photoUrl': participant.photoUrl,
                  },
                )
                .toList(),
            'unreadCountByUser': nextRoom.unreadCountByUser,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
      });
      return const Success<void>(null);
    } on FirebaseException catch (error) {
      return FailureResult<void>(
        _mapFailure(error, 'The chat participants could not be changed.'),
      );
    } catch (error) {
      return FailureResult<void>(InfrastructureFailure(error.toString()));
    }
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) {
      return const <String>[];
    }
    return value.whereType<String>().toList();
  }

  static Map<String, int> _intMap(Object? value) {
    if (value is! Map) {
      return <String, int>{};
    }
    final result = <String, int>{};
    value.forEach((key, value) {
      if (key is String && value is num) {
        result[key] = value.toInt();
      }
    });
    return result;
  }

  Failure _mapFailure(FirebaseException error, String fallback) {
    switch (error.code) {
      case 'permission-denied':
      case 'unauthenticated':
        return AuthorizationFailure(error.message ?? fallback);
      case 'invalid-argument':
      case 'failed-precondition':
      case 'not-found':
        return ValidationFailure(error.message ?? fallback);
      default:
        return InfrastructureFailure(error.message ?? fallback);
    }
  }
}
