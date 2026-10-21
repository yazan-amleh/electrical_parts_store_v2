import '../../../../core/result/result.dart';
import '../entities/authenticated_user.dart';

abstract interface class AuthRepository {
  AuthenticatedUser? get currentUser;

  Stream<AuthenticatedUser?> authStateChanges();

  Future<Result<AuthenticatedUser>> signInWithEmailPassword({
    required String email,
    required String password,
  });

  Future<Result<AuthenticatedUser>> createUserWithEmailPassword({
    required String email,
    required String password,
    String? displayName,
  });

  Future<Result<void>> sendPasswordResetEmail({
    required String email,
  });

  Future<Result<void>> signOut();
}
