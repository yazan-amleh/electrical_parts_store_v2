import '../../../../core/result/result.dart';
import '../entities/authenticated_user.dart';

/// Updates only the current Firebase identity, never a store membership or
/// another user's profile. Passwords must not be written to Firestore.
abstract interface class AccountProfileRepository {
  Future<Result<AuthenticatedUser>> getProfile({
    required String expectedUserId,
  });

  Future<Result<AuthenticatedUser>> updateDisplayName({
    required String expectedUserId,
    required String displayName,
  });

  Future<Result<void>> changePassword({
    required String expectedUserId,
    required String currentPassword,
    required String newPassword,
  });
}
