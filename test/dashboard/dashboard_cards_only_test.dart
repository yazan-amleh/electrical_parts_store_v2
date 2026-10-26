import 'package:electrical_parts_store_v2/features/auth/domain/entities/authenticated_user.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/store_membership.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/enums/store_role.dart';
import 'package:electrical_parts_store_v2/features/dashboard/presentation/dashboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget screen(String storeId) => MaterialApp(
        home: Scaffold(
          body: DashboardPage(
            accountingQueryRepository: null,
            productRepository: null,
            user: const AuthenticatedUser(
              id: 'user-one',
              email: 'user@example.com',
            ),
            membership: StoreMembership(
              storeId: storeId,
              userId: 'user-one',
              role: StoreRole.owner,
            ),
            onOpenModule: (_) {},
          ),
        ),
      );

  testWidgets('V1 cards-only mode persists and hides accounting warnings',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(screen('store-one'));
    await tester.pumpAndSettle();

    expect(find.text('مستودعات لوحة التحكم غير موصولة بهذه البيئة.'),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('dashboard-shortcuts-only')));
    await tester.pumpAndSettle();
    expect(find.text('مستودعات لوحة التحكم غير موصولة بهذه البيئة.'),
        findsNothing);
    expect(find.text('اختصارات العمل'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('v2:dashboard-cards-only:store-one:user-one'), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(screen('store-one'));
    await tester.pumpAndSettle();
    expect(find.text('مستودعات لوحة التحكم غير موصولة بهذه البيئة.'),
        findsNothing);

    await tester.pumpWidget(screen('store-two'));
    await tester.pumpAndSettle();
    expect(find.text('مستودعات لوحة التحكم غير موصولة بهذه البيئة.'),
        findsOneWidget);
  });
}
