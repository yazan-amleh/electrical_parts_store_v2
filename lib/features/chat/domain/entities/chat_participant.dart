class ChatParticipant {
  ChatParticipant({
    required this.userId,
    this.displayName,
    required this.joinedAt,
    this.isAdmin = false,
    this.photoUrl,
  }) {
    if (userId.trim().isEmpty || userId.contains('/')) {
      throw ArgumentError('Chat participant id is invalid.');
    }
  }

  final String userId;
  final String? displayName;
  final DateTime joinedAt;
  final bool isAdmin;
  final String? photoUrl;

  ChatParticipant copyWith({
    String? displayName,
    DateTime? joinedAt,
    bool? isAdmin,
    String? photoUrl,
  }) {
    return ChatParticipant(
      userId: userId,
      displayName: displayName ?? this.displayName,
      joinedAt: joinedAt ?? this.joinedAt,
      isAdmin: isAdmin ?? this.isAdmin,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }
}
