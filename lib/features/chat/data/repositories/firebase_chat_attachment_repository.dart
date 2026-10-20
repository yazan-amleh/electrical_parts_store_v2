import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../domain/entities/chat_attachment.dart';
import '../../domain/repositories/chat_attachment_repository.dart';

class FirebaseChatAttachmentRepository
    implements ChatAttachmentRepository {
  FirebaseChatAttachmentRepository({required FirebaseStorage storage})
      : _storage = storage;

  final FirebaseStorage _storage;

  static final _unsafeFileName = RegExp(r'[^A-Za-z0-9._-]');
  static final _repeatedUnderscore = RegExp(r'_+');

  @override
  Future<Result<ChatAttachment>> upload({
    required StoreContext context,
    required String roomId,
    required String fileName,
    required Uint8List bytes,
    String? contentType,
  }) async {
    final normalizedRoomId = roomId.trim();
    final normalizedFileName = fileName.trim();
    if (context.storeId.trim().isEmpty ||
        context.userId.trim().isEmpty ||
        normalizedRoomId.isEmpty ||
        normalizedRoomId.contains('/') ||
        normalizedFileName.isEmpty ||
        bytes.isEmpty) {
      return const FailureResult<ChatAttachment>(
        ValidationFailure('A valid room, file name and file are required.'),
      );
    }
    if (bytes.length > ChatAttachmentRepository.maxAttachmentBytes) {
      return const FailureResult<ChatAttachment>(
        ValidationFailure('Chat attachments must be 10 MB or smaller.'),
      );
    }

    final safeFileName = _safeFileName(normalizedFileName);
    final attachmentId =
        DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36);
    final storagePath = [
      'stores',
      context.storeId,
      'chatRooms',
      normalizedRoomId,
      'attachments',
      context.userId,
      '$attachmentId-$safeFileName',
    ].join('/');
    final reference = _storage.ref(storagePath);

    try {
      await reference.putData(
        bytes,
        SettableMetadata(
          contentType: _contentType(contentType, safeFileName),
          customMetadata: <String, String>{
            'storeId': context.storeId,
            'roomId': normalizedRoomId,
            'ownerId': context.userId,
            'attachmentId': attachmentId,
          },
        ),
      );
      final downloadUrl = await reference.getDownloadURL();
      final uploadedAt = DateTime.now().toUtc();
      return Success<ChatAttachment>(
        ChatAttachment(
          id: attachmentId,
          storeId: context.storeId,
          roomId: normalizedRoomId,
          ownerId: context.userId,
          fileName: normalizedFileName,
          contentType: _contentType(contentType, safeFileName),
          sizeBytes: bytes.length,
          storagePath: storagePath,
          downloadUrl: downloadUrl,
          uploadedAt: uploadedAt,
        ),
      );
    } on FirebaseException catch (error) {
      return FailureResult<ChatAttachment>(
        _mapFailure(error, 'The chat attachment could not be uploaded.'),
      );
    } catch (error) {
      return FailureResult<ChatAttachment>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<void>> delete({
    required StoreContext context,
    required ChatAttachment attachment,
  }) async {
    final expectedPrefix = [
      'stores',
      context.storeId,
      'chatRooms',
      attachment.roomId,
      'attachments',
      context.userId,
      '',
    ].join('/');
    if (attachment.ownerId != context.userId ||
        !attachment.storagePath.startsWith(expectedPrefix)) {
      return const FailureResult<void>(
        AuthorizationFailure('Only the attachment owner can delete it.'),
      );
    }

    try {
      await _storage.ref(attachment.storagePath).delete();
      return const Success<void>(null);
    } on FirebaseException catch (error) {
      return FailureResult<void>(
        _mapFailure(error, 'The chat attachment could not be deleted.'),
      );
    } catch (error) {
      return FailureResult<void>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  static String _safeFileName(String fileName) {
    final sanitized = fileName
        .replaceAll(_unsafeFileName, '_')
        .replaceAll(_repeatedUnderscore, '_');
    final normalized = sanitized.isEmpty ? 'attachment' : sanitized;
    return normalized.length > 80 ? normalized.substring(0, 80) : normalized;
  }

  static String _contentType(String? contentType, String fileName) {
    final normalized = contentType?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      return normalized;
    }
    final extension = fileName.contains('.') ? fileName.split('.').last : '';
    switch (extension.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  Failure _mapFailure(FirebaseException error, String fallback) {
    switch (error.code) {
      case 'permission-denied':
      case 'unauthenticated':
        return AuthorizationFailure(error.message ?? fallback);
      case 'invalid-argument':
      case 'object-not-found':
        return ValidationFailure(error.message ?? fallback);
      default:
        return InfrastructureFailure(error.message ?? fallback);
    }
  }
}
