import 'package:electrical_parts_store_v2/features/auth/domain/entities/authenticated_user.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/store_membership.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/enums/store_role.dart';
import 'package:electrical_parts_store_v2/features/payments/presentation/vouchers_hub_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget screen(StoreRole role) => MaterialApp(
        home: Scaffold(
          body: VouchersHubPage(
            paymentRepository: null,
            voucherQueryRepository: null,
            user: const AuthenticatedUser(
              id: 'test-user',
              email: 'test@example.com',
            ),
            membership: StoreMembership(
              storeId: 'test-store',
              userId: 'test-user',
              role: role,
            ),
          ),
        ),
      );

  testWidgets('owner can switch between receipt, payment and activity',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(940, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(screen(StoreRole.owner));
    await tester.pumpAndSettle();

    expect(find.text('مركز السندات المالية'), findsOneWidget);
    expect(find.text('قبض'), findsOneWidget);
    expect(find.text('دفع'), findsOneWidget);
    expect(find.text('حركات'), findsOneWidget);

    await tester.tap(find.text('دفع'));
    await tester.pumpAndSettle();
    expect(find.text('دفع لمورد'), findsOneWidget);

    await tester.tap(find.text('حركات'));
    await tester.pumpAndSettle();
    expect(
        find.text('مستودع سجل السندات غير موصول بهذه البيئة.'), findsOneWidget);
  });

  testWidgets('sales role cannot access supplier payment tab', (tester) async {
    await tester.pumpWidget(screen(StoreRole.sales));
    await tester.pumpAndSettle();

    expect(find.text('قبض'), findsNothing);
    expect(find.text('دفع'), findsNothing);
    expect(find.text('حركات'), findsNothing);
  });

  testWidgets('viewer cannot see financial voucher content', (tester) async {
    await tester.pumpWidget(screen(StoreRole.viewer));
    await tester.pumpAndSettle();

    expect(find.text('قبض'), findsNothing);
    expect(find.text('دفع'), findsNothing);
    expect(find.text('حركات'), findsNothing);
    expect(
        find.text('لا تملك صلاحية الوصول إلى مركز السندات.'), findsOneWidget);
  });
}
