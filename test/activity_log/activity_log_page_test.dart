import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/activity_log/domain/entities/activity_log.dart';
import 'package:electrical_parts_store_v2/features/activity_log/domain/repositories/activity_log_repository.dart';
import 'package:electrical_parts_store_v2/features/activity_log/presentation/activity_log_page.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/authenticated_user.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/store_membership.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/enums/store_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ActivityRepository implements ActivityLogRepository {
  _ActivityRepository(this.logsByStore);

  final Map<String, List<ActivityLog>> logsByStore;
  final List<StoreContext> calls = <StoreContext>[];
  final List<DateTime?> fromDates = <DateTime?>[];
  final List<DateTime?> toDates = <DateTime?>[];

  @override
  Stream<Result<List<ActivityLog>>> watchLogs({
    required StoreContext context,
    int limit = 100,
    DateTime? fromInclusive,
    DateTime? toExclusive,
  }) {
    calls.add(context);
    fromDates.add(fromInclusive);
    toDates.add(toExclusive);
    return Stream<Result<List<ActivityLog>>>.value(
      Success<List<ActivityLog>>(
        (logsByStore[context.storeId] ?? const <ActivityLog>[])
            .where(
              (log) =>
                  (fromInclusive == null ||
                      !log.occurredAt.isBefore(fromInclusive)) &&
                  (toExclusive == null || log.occurredAt.isBefore(toExclusive)),
            )
            .take(limit)
            .toList(growable: false),
      ),
    );
  }
}

const _user = AuthenticatedUser(
  id: 'user-1',
  email: 'user@example.com',
);

StoreMembership _membership(String storeId) {
  return StoreMembership(
    storeId: storeId,
    userId: _user.id,
    role: StoreRole.owner,
  );
}

ActivityLog _log({
  required String id,
  required String storeId,
  required String description,
  required ActivityType type,
}) {
  return ActivityLog(
    id: id,
    storeId: storeId,
    type: type,
    description: description,
    occurredAt: DateTime.now().toUtc(),
    userId: _user.id,
  );
}

Widget _page(
  ActivityLogRepository repository,
  StoreMembership membership,
) {
  return MaterialApp(
    home: ActivityLogPage(
      repository: repository,
      user: _user,
      membership: membership,
    ),
  );
}

void main() {
  testWidgets('rebinds activity stream when the active store changes', (
    tester,
  ) async {
    final repository = _ActivityRepository({
      'store-a': [
        _log(
          id: 'a',
          storeId: 'store-a',
          description: 'حدث المتجر أ',
          type: ActivityType.saleCreated,
        ),
      ],
      'store-b': [
        _log(
          id: 'b',
          storeId: 'store-b',
          description: 'حدث المتجر ب',
          type: ActivityType.purchasePosted,
        ),
      ],
    });

    await tester.pumpWidget(_page(repository, _membership('store-a')));
    await tester.pumpAndSettle();

    expect(find.text('حدث المتجر أ'), findsOneWidget);
    expect(repository.calls.last.storeId, 'store-a');

    await tester.pumpWidget(_page(repository, _membership('store-b')));
    await tester.pumpAndSettle();

    expect(find.text('حدث المتجر أ'), findsNothing);
    expect(find.text('حدث المتجر ب'), findsOneWidget);
    expect(repository.calls.last.storeId, 'store-b');
  });

  testWidgets('search filters the loaded activity feed', (tester) async {
    final repository = _ActivityRepository({
      'store-a': [
        _log(
          id: 'sale',
          storeId: 'store-a',
          description: 'تم بيع قاطع كهربائي',
          type: ActivityType.saleCreated,
        ),
        _log(
          id: 'expense',
          storeId: 'store-a',
          description: 'تم تسجيل مصروف نقل',
          type: ActivityType.expensePosted,
        ),
      ],
    });

    await tester.pumpWidget(_page(repository, _membership('store-a')));
    await tester.pumpAndSettle();

    expect(find.text('تم بيع قاطع كهربائي'), findsOneWidget);
    expect(find.text('تم تسجيل مصروف نقل'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'قاطع');
    await tester.pump();

    expect(find.text('تم بيع قاطع كهربائي'), findsOneWidget);
    expect(find.text('تم تسجيل مصروف نقل'), findsNothing);
  });

  testWidgets('changing the period rebinds a server-side bounded query', (
    tester,
  ) async {
    final now = DateTime.now();
    final repository = _ActivityRepository({
      'store-a': [
        ActivityLog(
          id: 'old',
          storeId: 'store-a',
          type: ActivityType.system,
          description: 'حدث قديم',
          occurredAt: now.subtract(const Duration(days: 60)),
        ),
        _log(
          id: 'new',
          storeId: 'store-a',
          description: 'حدث اليوم',
          type: ActivityType.system,
        ),
      ],
    });

    await tester.pumpWidget(_page(repository, _membership('store-a')));
    await tester.pumpAndSettle();

    expect(find.text('حدث اليوم'), findsOneWidget);
    expect(find.text('حدث قديم'), findsNothing);
    expect(repository.fromDates.last, isNotNull);
    expect(repository.toDates.last, isNotNull);

    await tester.tap(find.text('الكل'));
    await tester.pumpAndSettle();

    expect(repository.fromDates.last, isNull);
    expect(repository.toDates.last, isNull);
    expect(find.text('حدث قديم'), findsOneWidget);

    await tester.tap(find.text('هذا الأسبوع'));
    await tester.pumpAndSettle();

    expect(repository.fromDates.last, isNotNull);
    expect(repository.toDates.last, isNotNull);
    expect(find.text('حدث قديم'), findsNothing);
  });

  testWidgets('canceling custom date selection keeps the existing query', (
    tester,
  ) async {
    final repository = _ActivityRepository({'store-a': []});
    await tester.pumpWidget(_page(repository, _membership('store-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الكل'));
    await tester.pumpAndSettle();

    final callCount = repository.calls.length;
    await tester.tap(find.text('مدة مخصصة'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(repository.calls.length, callCount);
    expect(repository.fromDates.last, isNull);
    expect(repository.toDates.last, isNull);
  });
}
