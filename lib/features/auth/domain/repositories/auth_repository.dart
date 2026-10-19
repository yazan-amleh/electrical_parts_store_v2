import '../../../../core/result/result.dart';
import '../entities/authenticated_user.dart';

abstract interface class AuthRepository {
  AuthenticatedUser? get currentUser;

  Stream<AuthenticatedUser?> authStateChanges();

  Future<Result<AuthenticatedUser>> signInWithEmailPassword({
    required String email,
    required String password,
  });

  Future<Result<void>> signOut();
}
