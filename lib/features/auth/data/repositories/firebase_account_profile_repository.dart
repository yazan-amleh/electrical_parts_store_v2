import 'package:firebase_auth/firebase_auth.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/authenticated_user.dart';
import '../../domain/repositories/account_profile_repository.dart';

/// Uses Firebase Auth only; no store profile fields and no password storage.
class FirebaseAccountProfileRepository implements AccountProfileRepository {
  FirebaseAccountProfileRepository({required FirebaseAuth auth}) : _auth = auth;

  final FirebaseAuth _auth;

  User? _userFor(String expectedUserId) {
    final user = _auth.currentUser;
    return expectedUserId.trim().isNotEmpty && user?.uid == expectedUserId
        ? user
        : null;
  }

  AuthenticatedUser _snapshot(User user) => AuthenticatedUser(
        id: user.uid,
        email: user.email ?? '',
        displayName: user.displayName,
        isEmailVerified: user.emailVerified,
      );

  @override
  Future<Result<AuthenticatedUser>> getProfile({
    required String expectedUserId,
  }) async {
    final user = _userFor(expectedUserId);
    if (user == null) {
      return const FailureResult<AuthenticatedUser>(
        AuthorizationFailure('يرجى تسجيل الدخول بالحساب الصحيح.'),
      );
    }
    try {
      await user.reload();
      final refreshed = _userFor(expectedUserId);
      if (refreshed == null) {
        return const FailureResult<AuthenticatedUser>(
          AuthorizationFailure('تغيّرت جلسة الحساب أثناء التحميل.'),
        );
      }
      return Success<AuthenticatedUser>(_snapshot(refreshed));
    } on FirebaseAuthException catch (error) {
      return FailureResult<AuthenticatedUser>(
        AuthorizationFailure(_message(error)),
      );
    } catch (_) {
      return const FailureResult<AuthenticatedUser>(
        InfrastructureFailure('تعذر تحميل المعلومات الشخصية.'),
      );
    }
  }

  @override
  Future<Result<AuthenticatedUser>> updateDisplayName({
    required String expectedUserId,
    required String displayName,
  }) async {
    final name = displayName.trim();
    if (name.isEmpty || name.length > 80) {
      return const FailureResult<AuthenticatedUser>(
        ValidationFailure('الاسم مطلوب ويجب ألا يزيد عن 80 حرفًا.'),
      );
    }
    final user = _userFor(expectedUserId);
    if (user == null) {
      return const FailureResult<AuthenticatedUser>(
        AuthorizationFailure('لا يمكن تعديل حساب آخر.'),
      );
    }
    try {
      await user.updateDisplayName(name);
      if (_userFor(expectedUserId) == null) {
        return const FailureResult<AuthenticatedUser>(
          AuthorizationFailure('تغيّرت جلسة الحساب أثناء التعديل.'),
        );
      }
      await user.reload();
      final updated = _userFor(expectedUserId);
      if (updated == null) {
        return const FailureResult<AuthenticatedUser>(
          AuthorizationFailure('تغيّرت جلسة الحساب أثناء التعديل.'),
        );
      }
      return Success<AuthenticatedUser>(_snapshot(updated));
    } on FirebaseAuthException catch (error) {
      return FailureResult<AuthenticatedUser>(
        AuthorizationFailure(_message(error)),
      );
    } catch (_) {
      return const FailureResult<AuthenticatedUser>(
        InfrastructureFailure('تعذر تحديث الاسم الشخصي.'),
      );
    }
  }

  @override
  Future<Result<void>> changePassword({
    required String expectedUserId,
    required String currentPassword,
    required String newPassword,
  }) async {
    if (currentPassword.isEmpty ||
        newPassword.length < 8 ||
        newPassword == currentPassword) {
      return const FailureResult<void>(
        ValidationFailure(
          'أدخل الكلمة الحالية وكلمة جديدة مختلفة لا تقل عن 8 أحرف.',
        ),
      );
    }
    final user = _userFor(expectedUserId);
    final email = user?.email;
    if (user == null || email == null || email.trim().isEmpty) {
      return const FailureResult<void>(
        AuthorizationFailure('الحساب الحالي لا يدعم تغيير كلمة المرور هنا.'),
      );
    }
    if (!user.providerData
        .any((provider) => provider.providerId == 'password')) {
      return const FailureResult<void>(
        AuthorizationFailure(
            'الحساب غير مرتبط بتسجيل دخول البريد وكلمة المرور.'),
      );
    }
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(
          email: email,
          password: currentPassword,
        ),
      );
      if (_userFor(expectedUserId) == null) {
        return const FailureResult<void>(
          AuthorizationFailure('تغيّرت جلسة الحساب أثناء إعادة التحقق.'),
        );
      }
      await user.updatePassword(newPassword);
      return const Success<void>(null);
    } on FirebaseAuthException catch (error) {
      return FailureResult<void>(AuthorizationFailure(_message(error)));
    } catch (_) {
      return const FailureResult<void>(
        InfrastructureFailure('تعذر تغيير كلمة المرور.'),
      );
    }
  }

  String _message(FirebaseAuthException error) {
    switch (error.code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'كلمة المرور الحالية غير صحيحة.';
      case 'weak-password':
        return 'كلمة المرور الجديدة ضعيفة.';
      case 'requires-recent-login':
        return 'يلزم إعادة تسجيل الدخول للتحقق من الحساب.';
      case 'too-many-requests':
        return 'محاولات كثيرة. حاول لاحقًا.';
      case 'network-request-failed':
        return 'تعذر الاتصال بخدمة الحساب.';
      case 'user-disabled':
      case 'user-not-found':
        return 'الحساب غير متاح حاليًا.';
      default:
        return error.message ?? 'تعذر إكمال الطلب.';
    }
  }
}
