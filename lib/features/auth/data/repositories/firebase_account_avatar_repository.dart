import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/repositories/account_avatar_repository.dart';

class FirebaseAccountAvatarRepository implements AccountAvatarRepository {
  FirebaseAccountAvatarRepository({
    required FirebaseAuth auth,
    required FirebaseStorage storage,
  })  : _auth = auth,
        _storage = storage;

  final FirebaseAuth _auth;
  final FirebaseStorage _storage;

  bool _owns(String expectedUserId) =>
      expectedUserId.trim().isNotEmpty &&
      _auth.currentUser?.uid == expectedUserId;

  Reference _avatar(String uid) =>
      _storage.ref().child('users/$uid/avatar/photo');

  @override
  Future<Result<Uint8List?>> load({
    required String expectedUserId,
  }) async {
    if (!_owns(expectedUserId)) {
      return const FailureResult<Uint8List?>(
        AuthorizationFailure('لا يمكن قراءة صورة حساب آخر.'),
      );
    }
    try {
      final bytes = await _avatar(expectedUserId).getData(
        AccountAvatarValidation.maxBytes,
      );
      if (!_owns(expectedUserId)) {
        return const FailureResult<Uint8List?>(
          AuthorizationFailure('تغيّرت جلسة الحساب.'),
        );
      }
      if (bytes == null) return const Success<Uint8List?>(null);
      if (AccountAvatarValidation.mimeType(bytes) == null) {
        return const FailureResult<Uint8List?>(
          ValidationFailure('ملف الصورة المحفوظ غير صالح.'),
        );
      }
      return Success<Uint8List?>(bytes);
    } on FirebaseException catch (error) {
      if (error.code == 'object-not-found' && _owns(expectedUserId)) {
        return const Success<Uint8List?>(null);
      }
      return FailureResult<Uint8List?>(
        InfrastructureFailure('تعذر قراءة الصورة الشخصية: ${error.code}'),
      );
    } catch (_) {
      return const FailureResult<Uint8List?>(
        InfrastructureFailure('تعذر قراءة الصورة الشخصية.'),
      );
    }
  }

  @override
  Future<Result<Uint8List>> upload({
    required String expectedUserId,
    required Uint8List bytes,
  }) async {
    if (!_owns(expectedUserId)) {
      return const FailureResult<Uint8List>(
        AuthorizationFailure('لا يمكن تغيير صورة حساب آخر.'),
      );
    }
    final mimeType = AccountAvatarValidation.mimeType(bytes);
    if (mimeType == null) {
      return const FailureResult<Uint8List>(
        ValidationFailure(
          'مسموح بصور PNG أو JPEG سليمة بحجم لا يتجاوز 2MB.',
        ),
      );
    }
    try {
      await _avatar(expectedUserId).putData(
        bytes,
        SettableMetadata(
          contentType: mimeType,
          cacheControl: 'private, max-age=0',
        ),
      );
      if (!_owns(expectedUserId)) {
        return const FailureResult<Uint8List>(
          AuthorizationFailure('تغيّرت جلسة الحساب أثناء رفع الصورة.'),
        );
      }
      // Keep images private in Storage; never create a public download token.
      return Success<Uint8List>(bytes);
    } on FirebaseException catch (error) {
      return FailureResult<Uint8List>(
        InfrastructureFailure('تعذر رفع الصورة الشخصية: ${error.code}'),
      );
    } catch (_) {
      return const FailureResult<Uint8List>(
        InfrastructureFailure('تعذر رفع الصورة الشخصية.'),
      );
    }
  }
}
