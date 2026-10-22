/// Prevents accidentally running a configured environment against another Firebase project.
/// This class has no Firebase SDK dependency and can be tested in isolation.
abstract final class FirebaseProjectGuard {
  static void requireMatchingProject({
    required String expectedProjectId,
    required String actualProjectId,
  }) {
    final expected = expectedProjectId.trim();
    final actual = actualProjectId.trim();
    if (expected.isEmpty || actual.isEmpty || expected != actual) {
      throw StateError(
        'Firebase project mismatch: application configuration and initialized '
        'Firebase app refer to different projects. Startup has been stopped.',
      );
    }
  }
}
