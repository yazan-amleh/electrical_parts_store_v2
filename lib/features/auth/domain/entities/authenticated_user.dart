class AuthenticatedUser {
  const AuthenticatedUser({
    required this.id,
    required this.email,
    this.displayName,
    this.isEmailVerified = false,
  });

  final String id;
  final String email;
  final String? displayName;
  final bool isEmailVerified;
}
