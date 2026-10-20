import 'dart:typed_data';

import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/chat_attachment.dart';

abstract interface class ChatAttachmentRepository {
  static const maxAttachmentBytes = 10 * 1024 * 1024;

  Future<Result<ChatAttachment>> upload({ 
    required StoreContext context,
    required String roomId,
    required String fileName,
    required Uint8List bytes,
    String? contentType,
  });

  Future<Result<void>> delete({
    required StoreContext context,
    required ChatAttachment attachment,
  });
}
