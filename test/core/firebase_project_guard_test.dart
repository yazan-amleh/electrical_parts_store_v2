import 'package:flutter_test/flutter_test.dart';
import 'package:electrical_parts_store_v2/core/config/firebase_project_guard.dart';

void main() {
  group('FirebaseProjectGuard', () {
    test('accepts the configured V2 Firebase project', () {
      expect(
        () => FirebaseProjectGuard.requireMatchingProject(
          expectedProjectId: 'electrical-store-v2-prod',
          actualProjectId: 'electrical-store-v2-prod',
        ),
        returnsNormally,
      );
    });

    test('rejects a different Firebase project', () {
      expect(
        () => FirebaseProjectGuard.requireMatchingProject(
          expectedProjectId: 'electrical-store-v2-prod',
          actualProjectId: 'unrelated-project',
        ),
        throwsStateError,
      );
    });

    test('rejects an empty configured project ID', () {
      expect(
        () => FirebaseProjectGuard.requireMatchingProject(
          expectedProjectId: ' ',
          actualProjectId: 'electrical-store-v2-prod',
        ),
        throwsStateError,
      );
    });

    test('rejects an empty initialized Firebase project ID', () {
      expect(
        () => FirebaseProjectGuard.requireMatchingProject(
          expectedProjectId: 'electrical-store-v2-prod',
          actualProjectId: ' ',
        ),
        throwsStateError,
      );
    });
  });
}
