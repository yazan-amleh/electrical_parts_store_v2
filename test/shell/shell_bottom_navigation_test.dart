import 'package:electrical_parts_store_v2/features/auth/domain/enums/store_role.dart';
import 'package:electrical_parts_store_v2/features/shell/presentation/shell_bottom_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? opened;
  var moreCount = 0;

  setUp(() {
    opened = null;
    moreCount = 0;
  });

  Widget screen({
    required StoreRole role,
    required String activeId,
    List<String>? tabs,
    required ValueChanged<String> onNavigate,
    required VoidCallback onMore,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: const Center(child: Text('صفحة المتجر')),
        bottomNavigationBar: ShellBottomNavigation(
          activeModuleId: activeId,
          role: role,
          tabIds: tabs,
          onOpenModule: onNavigate,
          onMore: onMore,
        ),
      ),
    );
  }

  testWidgets('bottom tabs navigate to real V2 modules', (tester) async {
    await tester.pumpWidget(
      screen(
        role: StoreRole.owner,
        activeId: 'dashboard',
        onNavigate: (id) => opened = id,
        onMore: () => moreCount++,
      ),
    );

    await tester.tap(find.text('المبيعات'));
    expect(opened, 'sales');

    await tester.tap(find.text('القبض والدفع'));
    expect(opened, 'party-payments');

    await tester.tap(find.text('المزيد'));
    expect(moreCount, 1);
  });

  testWidgets('viewer has no write-oriented quick navigation', (tester) async {
    await tester.pumpWidget(
      screen(
        role: StoreRole.viewer,
        activeId: 'dashboard',
        onNavigate: (_) {},
        onMore: () {},
      ),
    );

    expect(find.text('المبيعات'), findsNothing);
    expect(find.text('القبض والدفع'), findsNothing);
    expect(find.text('الرئيسية'), findsOneWidget);
    expect(find.text('العملاء'), findsOneWidget);
    expect(find.text('المزيد'), findsOneWidget);
  });

  testWidgets('selected tabs are ordered and restricted by role',
      (tester) async {
    await tester.pumpWidget(
      screen(
        role: StoreRole.owner,
        activeId: 'inventory',
        tabs: const ['dashboard', 'inventory', 'notes'],
        onNavigate: (id) => opened = id,
        onMore: () {},
      ),
    );
    expect(find.text('المخزون'), findsOneWidget);
    expect(find.text('الملاحظات'), findsOneWidget);
    expect(find.text('المبيعات'), findsNothing);

    await tester.tap(find.text('المخزون'));
    expect(opened, 'inventory');

    await tester.pumpWidget(
      screen(
        role: StoreRole.viewer,
        activeId: 'dashboard',
        tabs: const ['sales', 'inventory', 'customers'],
        onNavigate: (_) {},
        onMore: () {},
      ),
    );
    await tester.pump();
    expect(find.text('المبيعات'), findsNothing);
    expect(find.text('المخزون'), findsNothing);
    expect(find.text('العملاء'), findsOneWidget);
  });

  testWidgets('compact bar fits a narrow phone viewport', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      screen(
        role: StoreRole.owner,
        activeId: 'dashboard',
        onNavigate: (_) {},
        onMore: () {},
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
  });

  testWidgets('non-tab destinations highlight More', (tester) async {
    await tester.pumpWidget(
      screen(
        role: StoreRole.owner,
        activeId: 'inventory',
        onNavigate: (_) {},
        onMore: () {},
      ),
    );

    final bar = tester.widget<BottomNavigationBar>(
      find.byType(BottomNavigationBar),
    );
    expect(bar.currentIndex, bar.items.length - 1);
  });
}
