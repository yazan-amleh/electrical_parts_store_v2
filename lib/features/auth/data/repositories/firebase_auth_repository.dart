import 'package:firebase_auth/firebase_auth.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/authenticated_user.dart';
import '../../domain/repositories/auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({required FirebaseAuth auth}) : _auth = auth;

  final FirebaseAuth _auth;

  @override
  AuthenticatedUser? get currentUser {
    final user = _auth.currentUser;
    return user == null ? null : _fromFirebaseUser(user);
  }

  @override
  Stream<AuthenticatedUser?> authStateChanges() {
    return _auth.authStateChanges().map(
          (user) => user == null ? null : _fromFirebaseUser(user),
        );
  }

  @override
  Future<Result<AuthenticatedUser>> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    if (email.trim().isEmpty || password.isEmpty) {
      return const FailureResult<AuthenticatedUser>(
        ValidationFailure('Email and password are required.'),
      );
    }

    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        return const FailureResult<AuthenticatedUser>(
          AuthorizationFailure(
            'Firebase did not return an authenticated user.',
          ),
        );
      }

      return Success<AuthenticatedUser>(_fromFirebaseUser(user));
    } on FirebaseAuthException catch (error) {
      return FailureResult<AuthenticatedUser>(
        AuthorizationFailure(_authMessage(error)),
      );
    } catch (error) {
      return FailureResult<AuthenticatedUser>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<AuthenticatedUser>> createUserWithEmailPassword({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty || password.isEmpty) {
      return const FailureResult<AuthenticatedUser>(
        ValidationFailure('Email and password are required.'),
      );
    }
    if (password.length < 6) {
      return const FailureResult<AuthenticatedUser>(
        ValidationFailure('Password must be at least 6 characters.'),
      );
    }

    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      var user = credential.user;
      if (user == null) {
        return const FailureResult<AuthenticatedUser>(
          AuthorizationFailure(
            'Firebase did not return an authenticated user.',
          ),
        );
      }

      final normalizedDisplayName = displayName?.trim() ?? '';
      if (normalizedDisplayName.isNotEmpty) {
        await user.updateDisplayName(normalizedDisplayName);
        await user.reload();
        user = _auth.currentUser ?? user;
      }

      return Success<AuthenticatedUser>(_fromFirebaseUser(user));
    } on FirebaseAuthException catch (error) {
      return FailureResult<AuthenticatedUser>(
        AuthorizationFailure(_authMessage(error)),
      );
    } catch (error) {
      return FailureResult<AuthenticatedUser>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<void>> sendPasswordResetEmail({
    required String email,
  }) async {
    if (email.trim().isEmpty) {
      return const FailureResult<void>(
        ValidationFailure('Email is required.'),
      );
    }

    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return const Success<void>(null);
    } on FirebaseAuthException catch (error) {
      return FailureResult<void>(
        AuthorizationFailure(_authMessage(error)),
      );
    } catch (error) {
      return FailureResult<void>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<void>> signOut() async {
    try {
      await _auth.signOut();
      return const Success<void>(null);
    } on FirebaseAuthException catch (error) {
      return FailureResult<void>(AuthorizationFailure(_authMessage(error)));
    } catch (error) {
      return FailureResult<void>(InfrastructureFailure(error.toString()));
    }
  }

  static AuthenticatedUser _fromFirebaseUser(User user) {
    return AuthenticatedUser(
      id: user.uid,
      email: user.email ?? '',
      displayName: user.displayName,
      isEmailVerified: user.emailVerified,
    );
  }

  static String _authMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'البريد الإلكتروني أو كلمة المرور غير صحيحة.';
      case 'invalid-email':
        return 'صيغة البريد الإلكتروني غير صحيحة.';
      case 'user-disabled':
        return 'هذا الحساب موقوف.';
      case 'too-many-requests':
        return 'محاولات كثيرة. حاول مرة أخرى لاحقًا.';
      case 'email-already-in-use':
        return 'هذا البريد مستخدم مسبقًا. سجّل الدخول أو استعد كلمة المرور.';
      case 'weak-password':
        return 'كلمة المرور ضعيفة. استخدم 6 أحرف على الأقل.';
      case 'operation-not-allowed':
        return 'تسجيل البريد وكلمة المرور غير مفعّل في Firebase Authentication.';
      case 'network-request-failed':
        return 'تعذر الاتصال بخدمة تسجيل الدخول. تحقق من الإنترنت وحاول مرة أخرى.';
      case 'invalid-api-key':
      case 'app-not-authorized':
        return 'إعداد Firebase غير صحيح لهذا التطبيق.';
      default:
        return error.message ?? 'تعذر إكمال عملية تسجيل الدخول.';
    }
  }
}
