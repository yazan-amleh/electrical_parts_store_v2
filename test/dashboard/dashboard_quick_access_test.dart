import 'package:electrical_parts_store_v2/features/auth/domain/enums/store_role.dart';
import 'package:electrical_parts_store_v2/features/dashboard/presentation/dashboard_quick_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget screen({
    StoreRole role = StoreRole.owner,
    required ValueChanged<String> onOpenModule,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DashboardQuickAccess(
            storeId: 'store-one',
            userId: 'user-one',
            role: role,
            onOpenModule: onOpenModule,
          ),
        ),
      ),
    );
  }

  testWidgets('quick cards open their actual shell module IDs', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? opened;
    await tester.pumpWidget(
      screen(onOpenModule: (moduleId) => opened = moduleId),
    );
    await tester.pumpAndSettle();

    expect(find.text('اختصارات العمل'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('shortcut-sales')));
    expect(opened, 'sales');
  });

  testWidgets('viewer only receives read-only shortcut choices',
      (tester) async {
    await tester.pumpWidget(
      screen(role: StoreRole.viewer, onOpenModule: (_) {}),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('shortcut-sales')), findsNothing);
    expect(find.byKey(const ValueKey('shortcut-journal')), findsNothing);
    expect(find.byKey(const ValueKey('shortcut-customers')), findsOneWidget);
  });

  testWidgets('custom selection persists for the same user and store',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(screen(onOpenModule: (_) {}));
    await tester.pumpAndSettle();

    await tester.tap(find.text('تخصيص'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'المبيعات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ الاختصارات'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('shortcut-sales')), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    final saved =
        prefs.getStringList('v2:dashboard-shortcuts:store-one:user-one');
    expect(saved, isNotNull);
    expect(saved, isNot(contains('sales')));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(screen(onOpenModule: (_) {}));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shortcut-sales')), findsNothing);
  });
}
