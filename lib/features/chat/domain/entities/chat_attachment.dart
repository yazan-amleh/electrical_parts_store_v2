class ChatAttachment {
  ChatAttachment({
    required this.id,
    required this.storeId,
    required this.roomId,
    required this.ownerId,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.storagePath,
    required this.downloadUrl,
    required this.uploadedAt,
  }) {
    if (id.trim().isEmpty ||
        storeId.trim().isEmpty ||
        roomId.trim().isEmpty ||
        ownerId.trim().isEmpty ||
        fileName.trim().isEmpty ||
        storagePath.trim().isEmpty ||
        downloadUrl.trim().isEmpty) {
      throw ArgumentError('Chat attachment identity fields are required.');
    }
    if (sizeBytes <= 0) {
      throw ArgumentError('Chat attachments must contain data.');
    }
  }

  final String id;
  final String storeId;
  final String roomId;
  final String ownerId;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final String storagePath;
  final String downloadUrl;
  final DateTime uploadedAt;
}
