import 'dart:typed_data';

import '../../../../core/result/result.dart';

/// Private profile images: access requires the same signed-in Firebase UID.
abstract interface class AccountAvatarRepository {
  Future<Result<Uint8List?>> load({
    required String expectedUserId,
  });

  Future<Result<Uint8List>> upload({
    required String expectedUserId,
    required Uint8List bytes,
  });
}

/// Keep client validation in sync with Storage rules; no file extension trust.
abstract final class AccountAvatarValidation {
  static const maxBytes = 2 * 1024 * 1024;

  static String? mimeType(Uint8List bytes) {
    if (bytes.length < 8 || bytes.length > maxBytes) return null;
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'image/png';
    }
    if (bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF &&
        bytes.last == 0xD9) {
      return 'image/jpeg';
    }
    return null;
  }
}
