import 'dart:typed_data';

import 'package:electrical_parts_store_v2/features/auth/domain/repositories/account_avatar_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts PNG signature and JPEG with end-of-image marker', () {
    expect(
      AccountAvatarValidation.mimeType(Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
      ])),
      'image/png',
    );
    expect(
      AccountAvatarValidation.mimeType(Uint8List.fromList([
        0xFF,
        0xD8,
        0xFF,
        0xE0,
        0x00,
        0x02,
        0x01,
        0xD9,
      ])),
      'image/jpeg',
    );
  });

  test('rejects GIF, forged extension, empty and oversized data', () {
    expect(
      AccountAvatarValidation.mimeType(
        Uint8List.fromList('GIF89a'.codeUnits),
      ),
      isNull,
    );
    expect(AccountAvatarValidation.mimeType(Uint8List(0)), isNull);
    expect(
      AccountAvatarValidation.mimeType(
        Uint8List(AccountAvatarValidation.maxBytes + 1),
      ),
      isNull,
    );
  });
}
