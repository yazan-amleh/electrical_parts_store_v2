import 'package:electrical_parts_store_v2/firebase_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Firebase native V2 configuration', () {
    test('does not allow Android startup without registered options', () {
      expect(
        () => FirebaseNativeConfiguration.build(
          platform: 'Android',
          apiKey: '',
          appId: '',
          senderId: '',
          projectId: '',
          storageBucket: '',
        ),
        throwsUnsupportedError,
      );
    });

    test('rejects use of a Web Firebase app ID for Android', () {
      expect(
        () => FirebaseNativeConfiguration.build(
          platform: 'Android',
          apiKey: 'test-only-key',
          appId: '1:123456:web:test',
          senderId: '123456',
          projectId: 'test-v2-project',
          storageBucket: 'test-v2-bucket',
        ),
        throwsArgumentError,
      );
    });

    test('rejects mismatched Firebase sender ID in native options', () {
      expect(
        () => FirebaseNativeConfiguration.build(
          platform: 'Android',
          apiKey: 'test-only-key',
          appId: '1:123456:android:test',
          senderId: '999999',
          projectId: 'test-v2-project',
          storageBucket: 'test-v2-bucket',
        ),
        throwsArgumentError,
      );
    });

    test('requires a registered iOS bundle identifier', () {
      expect(
        () => FirebaseNativeConfiguration.build(
          platform: 'iOS',
          apiKey: 'test-only-key',
          appId: '1:123456:ios:test',
          senderId: '123456',
          projectId: 'test-v2-project',
          storageBucket: 'test-v2-bucket',
        ),
        throwsUnsupportedError,
      );
    });

    test('accepts complete test-only native options', () {
      final result = FirebaseNativeConfiguration.build(
        platform: 'Android',
        apiKey: 'test-only-key',
        appId: '1:123456:android:test',
        senderId: '123456',
        projectId: 'test-v2-project',
        storageBucket: 'test-v2-bucket',
      );
      expect(result.projectId, 'test-v2-project');
      expect(result.appId, '1:123456:android:test');
    });
  });
}
