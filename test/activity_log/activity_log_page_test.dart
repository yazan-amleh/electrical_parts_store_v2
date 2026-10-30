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

  @override
  Stream<Result<List<ActivityLog>>> watchLogs({
    required StoreContext context,
    int limit = 100,
  }) {
    calls.add(context);
    return Stream<Result<List<ActivityLog>>>.value(
      Success<List<ActivityLog>>(
        (logsByStore[context.storeId] ?? const <ActivityLog>[])
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
}
