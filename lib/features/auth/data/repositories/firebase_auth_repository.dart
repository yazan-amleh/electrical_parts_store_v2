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
        return 'The email or password is incorrect.';
      case 'invalid-email':
        return 'The email address is invalid.';
      case 'user-disabled':
        return 'This user is disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      default:
        return error.message ?? 'Authentication failed.';
    }
  }
}
