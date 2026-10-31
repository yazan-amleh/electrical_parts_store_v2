import 'dart:async';

import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/authenticated_user.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/store_membership.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/enums/store_role.dart';
import 'package:electrical_parts_store_v2/features/reports/domain/entities/operational_report.dart';
import 'package:electrical_parts_store_v2/features/reports/domain/repositories/reports_repository.dart';
import 'package:electrical_parts_store_v2/features/reports/presentation/reports_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _OperationalReports implements ReportsRepository {
  final calls = <StoreContext>[];
  final pendingA = Completer<Result<OperationalReport>>();

  @override
  Future<Result<OperationalReport>> getOperationalReport({
    required StoreContext context,
    required DateTime from,
    required DateTime to,
    int limit = 500,
    int maxDocuments = 10000,
  }) {
    calls.add(context);
    if (context.storeId == 'store-a') return pendingA.future;
    return Future.value(Success(_report('store-b')));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

OperationalReport _report(String storeId) {
  return OperationalReport(
    from: DateTime.utc(2026, 10, 1),
    to: DateTime.utc(2026, 10, 31),
    salesRevenue: const Money(minorUnits: 15000),
    salesCost: const Money(minorUnits: 6000),
    purchasesTotal: const Money(minorUnits: 0),
    expensesTotal: const Money(minorUnits: 0),
    salesCount: 1,
    purchasesCount: 0,
    expensesCount: 0,
    salesByPaymentMethod: const {'cash': 1},
    expensesByPaymentMethod: const {},
    transactions: [
      ReportTransaction(
        id: 'receipt-$storeId',
        postedAt: DateTime.utc(2026, 10, 31),
        source: 'sale',
        amount: const Money(minorUnits: 15000),
        cost: const Money(minorUnits: 6000),
        description: 'مستند $storeId',
        paymentMethod: 'cash',
      ),
    ],
    mayBeTruncated: false,
  );
}

const user = AuthenticatedUser(id: 'user-1', email: 'a@example.com');

Widget _page(_OperationalReports repository, String storeId) {
  return MaterialApp(
    home: Scaffold(
      body: ReportsPage(
        repository: repository,
        documentBuilder: null,
        productRepository: null,
        user: user,
        membership: StoreMembership(
          storeId: storeId,
          userId: user.id,
          role: StoreRole.owner,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('old store report cannot replace the switched store report', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1300, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _OperationalReports();
    await tester.pumpWidget(_page(repository, 'store-a'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(_page(repository, 'store-b'));
    await tester.pumpAndSettle();
    expect(find.text('مستند store-b'), findsOneWidget);
    expect(repository.calls.last.storeId, 'store-b');

    repository.pendingA.complete(Success(_report('store-a')));
    await tester.pumpAndSettle();
    expect(find.text('مستند store-a'), findsNothing);
    expect(find.text('مستند store-b'), findsOneWidget);
  });

  testWidgets('operational report has period presets and real Excel export', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1300, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _OperationalReports();
    await tester.pumpWidget(_page(repository, 'store-b'));
    await tester.pumpAndSettle();
    expect(find.text('تنزيل Excel'), findsOneWidget);
    expect(find.text('هذا الأسبوع'), findsOneWidget);
    expect(find.text('هذا الشهر'), findsOneWidget);
    expect(find.text('هذه السنة'), findsOneWidget);
    expect(find.text('تفاصيل الحركات ضمن الفترة'), findsOneWidget);

    await tester.tap(find.text('هذا الأسبوع'));
    await tester.pumpAndSettle();
    final exportButton =
        tester.widget<OutlinedButton>(
          find.ancestor(
            of: find.text('تنزيل Excel'),
            matching: find.byType(OutlinedButton),
          ),
        );
    expect(exportButton.onPressed, isNull);
    await tester.tap(find.text('تطبيق الفترة'));
    await tester.pumpAndSettle();
    expect(repository.calls, hasLength(2));
  });
}
