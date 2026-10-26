import 'dart:async';

import 'package:electrical_parts_store_v2/core/errors/failure.dart';
import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/auth/application/auth_session_controller.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/authenticated_user.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/store_membership.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/repositories/auth_repository.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/repositories/store_membership_repository.dart';
import 'package:electrical_parts_store_v2/features/auth/presentation/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAuthRepository auth;
  late AuthSessionController controller;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    auth = _FakeAuthRepository();
    controller = AuthSessionController(
      authRepository: auth,
      membershipRepository: _NoMembershipRepository(),
      storeId: 'test-store',
    )..start();
  });

  tearDown(() async {
    controller.dispose();
    await auth.dispose();
  });

  testWidgets('V1 visual sign-in controls and accessible registration path',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 920));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester
        .pumpWidget(MaterialApp(home: LoginPage(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('مرحباً بك مجدداً'), findsOneWidget);
    expect(find.text('تسجيل الدخول'), findsWidgets);
    expect(find.text('تذكرني'), findsOneWidget);
    expect(find.text('نسيت كلمة المرور؟'), findsOneWidget);
    expect(find.text('ليس لديك حساب؟ إنشاء حساب جديد'), findsOneWidget);
    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));

    await tester.ensureVisible(find.text('ليس لديك حساب؟ إنشاء حساب جديد'));
    await tester.tap(find.text('ليس لديك حساب؟ إنشاء حساب جديد'));
    await tester.pumpAndSettle();
    expect(find.text('تأكيد كلمة المرور'), findsOneWidget);
    expect(find.text('الاسم'), findsOneWidget);
    expect(find.text('إنشاء حساب'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(4));
  });

  testWidgets('reset page is reachable and validates email', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 920));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester
        .pumpWidget(MaterialApp(home: LoginPage(controller: controller)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('نسيت كلمة المرور؟'));
    await tester.tap(find.text('نسيت كلمة المرور؟'));
    await tester.pumpAndSettle();

    expect(find.text('نسيت كلمة المرور؟'), findsOneWidget);
    await tester.ensureVisible(find.text('إرسال رابط إعادة التعيين'));
    await tester.tap(find.text('إرسال رابط إعادة التعيين'));
    await tester.pump();
    expect(find.text('الرجاء إدخال البريد الإلكتروني'), findsOneWidget);
    expect(auth.resetCalls, 0);
  });

  testWidgets('V1 auth layouts stay responsive at 320px and desktop widths',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in [const Size(320, 700), const Size(1200, 900)]) {
      await tester.binding.setSurfaceSize(size);
      await tester
          .pumpWidget(MaterialApp(home: LoginPage(controller: controller)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('تذكرني'), findsOneWidget);
      expect(find.text('نسيت كلمة المرور؟'), findsOneWidget);
    }
  });

  testWidgets('remember-me stores email only and never password',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 920));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester
        .pumpWidget(MaterialApp(home: LoginPage(controller: controller)));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextFormField).at(0), 'tester@example.com');
    await tester.enterText(
        find.byType(TextFormField).at(1), 'do-not-save-this');
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester
        .ensureVisible(find.widgetWithText(ElevatedButton, 'تسجيل الدخول'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'تسجيل الدخول'));
    await tester.pumpAndSettle();

    final saved = await SharedPreferences.getInstance();
    expect(saved.getBool('auth_remember_email'), isTrue);
    expect(saved.getString('auth_saved_email'), 'tester@example.com');
    expect(
        saved.getKeys().where((key) => key.toLowerCase().contains('password')),
        isEmpty);
    expect(
        saved.getKeys().map(saved.get).where(
            (value) => value is String && value.contains('do-not-save-this')),
        isEmpty);
  });
}

class _FakeAuthRepository implements AuthRepository {
  final _stream = StreamController<AuthenticatedUser?>.broadcast();
  int resetCalls = 0;

  @override
  AuthenticatedUser? get currentUser => null;

  @override
  Stream<AuthenticatedUser?> authStateChanges() => _stream.stream;

  @override
  Future<Result<AuthenticatedUser>> signInWithEmailPassword({
    required String email,
    required String password,
  }) async =>
      const FailureResult<AuthenticatedUser>(
        AuthorizationFailure('بيانات تسجيل الدخول غير صحيحة'),
      );

  @override
  Future<Result<AuthenticatedUser>> createUserWithEmailPassword({
    required String email,
    required String password,
    String? displayName,
  }) async =>
      const FailureResult<AuthenticatedUser>(
        AuthorizationFailure('بيانات التسجيل غير صحيحة'),
      );

  @override
  Future<Result<void>> sendPasswordResetEmail({required String email}) async {
    resetCalls++;
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> signOut() async => const Success<void>(null);

  Future<void> dispose() => _stream.close();
}

class _NoMembershipRepository implements StoreMembershipRepository {
  @override
  Future<Result<StoreMembership>> getMembership({
    required StoreContext context,
  }) async =>
      const FailureResult<StoreMembership>(
        StoreMembershipNotFoundFailure('Missing membership'),
      );
}
