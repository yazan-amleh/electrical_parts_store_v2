import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/chat_message.dart';
import '../entities/chat_participant.dart';
import '../entities/chat_room.dart';
import '../enums/chat_enums.dart';

abstract interface class ChatRepository {
  Stream<Result<List<ChatRoom>>> watchRooms({
    required StoreContext context,
  });

  Stream<Result<List<ChatMessage>>> watchMessages({
    required StoreContext context,
    required String roomId,
  });

  Future<Result<ChatRoom>> createRoom({
    required StoreContext context,
    required String name,
    required List<ChatParticipant> participants,
    required ChatRoomType type,
    String? groupDescription,
  });

  Future<Result<ChatMessage>> sendMessage({
    required StoreContext context,
    required String roomId,
    required String senderName,
    required String content,
    ChatMessageType type = ChatMessageType.text,
    List<String> attachmentUrls = const [],
  });

  Future<Result<void>> markRoomRead({
    required StoreContext context,
    required String roomId,
  });

  Future<Result<void>> updateRoom({
    required StoreContext context,
    required String roomId,
    String? name,
    String? groupDescription,
  });

  Future<Result<void>> addParticipant({
    required StoreContext context,
    required String roomId,
    required ChatParticipant participant,
  });

  Future<Result<void>> removeParticipant({
    required StoreContext context,
    required String roomId,
    required String userId,
  });

  Future<Result<void>> archiveRoom({
    required StoreContext context,
    required String roomId,
  });
}
