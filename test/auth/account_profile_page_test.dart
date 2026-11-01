import 'dart:async';

import 'package:electrical_parts_store_v2/core/errors/failure.dart';
import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/authenticated_user.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/repositories/account_profile_repository.dart';
import 'package:electrical_parts_store_v2/features/auth/presentation/account_profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _AccountRepository implements AccountProfileRepository {
  final requests = <String>[];
  final nameChanges = <(String, String)>[];
  final passwords = <(String, String, String)>[];
  Completer<Result<AuthenticatedUser>>? slowLoad;
  bool failPassword = false;

  @override
  Future<Result<AuthenticatedUser>> getProfile({
    required String expectedUserId,
  }) {
    requests.add(expectedUserId);
    if (expectedUserId == 'a' && slowLoad != null) {
      return slowLoad!.future;
    }
    return Future.value(
      Success(AuthenticatedUser(
        id: expectedUserId,
        email: '$expectedUserId@example.com',
        displayName: 'مستخدم $expectedUserId',
        isEmailVerified: true,
      )),
    );
  }

  @override
  Future<Result<AuthenticatedUser>> updateDisplayName({
    required String expectedUserId,
    required String displayName,
  }) async {
    nameChanges.add((expectedUserId, displayName));
    return Success(AuthenticatedUser(
      id: expectedUserId,
      email: '$expectedUserId@example.com',
      displayName: displayName.trim(),
    ));
  }

  @override
  Future<Result<void>> changePassword({
    required String expectedUserId,
    required String currentPassword,
    required String newPassword,
  }) async {
    passwords.add((expectedUserId, currentPassword, newPassword));
    if (failPassword) {
      return const FailureResult<void>(
        AuthorizationFailure('كلمة المرور الحالية غير صحيحة.'),
      );
    }
    return const Success<void>(null);
  }
}

Widget _profile(_AccountRepository repository, String userId) {
  return MaterialApp(
    home: AccountProfilePage(
      key: const ValueKey('profile'),
      repository: repository,
      user: AuthenticatedUser(
        id: userId,
        email: '$userId@example.com',
      ),
    ),
  );
}

void main() {
  testWidgets('personal profile loads the correct identity and updates name',
      (tester) async {
    final repository = _AccountRepository();
    await tester.pumpWidget(_profile(repository, 'a'));
    await tester.pumpAndSettle();
    expect(find.text('المعلومات الشخصية'), findsOneWidget);
    expect(find.textContaining('a@example.com'), findsOneWidget);
    expect(find.text('حسابي والمعلومات الشخصية'), findsNothing);
    await tester.enterText(
      find.byType(TextFormField).first,
      'اسم محدث',
    );
    await tester.tap(find.text('حفظ المعلومات الشخصية'));
    await tester.pumpAndSettle();
    expect(repository.nameChanges, [('a', 'اسم محدث')]);
  });

  testWidgets('a late old-user response never appears in the new profile',
      (tester) async {
    final repository = _AccountRepository();
    repository.slowLoad = Completer<Result<AuthenticatedUser>>();
    await tester.pumpWidget(_profile(repository, 'a'));
    await tester.pump();
    await tester.pumpWidget(_profile(repository, 'b'));
    await tester.pumpAndSettle();
    expect(find.textContaining('b@example.com'), findsOneWidget);
    repository.slowLoad!.complete(const Success(
      AuthenticatedUser(
        id: 'a',
        email: 'a@example.com',
        displayName: 'سجل A',
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('سجل A'), findsNothing);
    expect(find.textContaining('b@example.com'), findsOneWidget);
    expect(repository.requests, ['a', 'b']);
  });

  testWidgets('password validation keeps invalid credentials off repository',
      (tester) async {
    final repository = _AccountRepository();
    await tester.pumpWidget(MaterialApp(
      home: ChangeAccountPasswordPage(
        repository: repository,
        expectedUserId: 'a',
      ),
    ));
    await tester.enterText(find.byType(TextFormField).at(0), 'old-secret');
    await tester.enterText(find.byType(TextFormField).at(1), '123');
    await tester.enterText(find.byType(TextFormField).at(2), 'wrong');
    await tester.testTextInput.hide();
    final save = find.byKey(const Key('change-account-password-submit'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repository.passwords, isEmpty);
    expect(find.textContaining('8 أحرف'), findsOneWidget);
    expect(find.textContaining('غير متطابقتين'), findsOneWidget);

    await tester.enterText(
      find.byType(TextFormField).at(1),
      'new-password-safe',
    );
    await tester.enterText(
      find.byType(TextFormField).at(2),
      'new-password-safe',
    );
    await tester.testTextInput.hide();
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(
      repository.passwords,
      [('a', 'old-secret', 'new-password-safe')],
    );
    expect(find.text('تم تغيير كلمة المرور'), findsOneWidget);
  });

  testWidgets('failed reauthentication never reports success', (tester) async {
    final repository = _AccountRepository()..failPassword = true;
    await tester.pumpWidget(MaterialApp(
      home: ChangeAccountPasswordPage(
        repository: repository,
        expectedUserId: 'b',
      ),
    ));
    await tester.enterText(find.byType(TextFormField).at(0), 'wrong-current');
    await tester.enterText(
        find.byType(TextFormField).at(1), 'new-password-safe');
    await tester.enterText(
        find.byType(TextFormField).at(2), 'new-password-safe');
    await tester.testTextInput.hide();
    final save = find.byKey(const Key('change-account-password-submit'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repository.passwords.single.$1, 'b');
    expect(find.text('تم تغيير كلمة المرور'), findsNothing);
    expect(find.text('كلمة المرور الحالية غير صحيحة.'), findsOneWidget);
  });
}
