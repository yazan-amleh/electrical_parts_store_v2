import 'dart:async';

import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/accounting/domain/entities/trial_balance.dart';
import 'package:electrical_parts_store_v2/features/accounting/domain/repositories/accounting_query_repository.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/authenticated_user.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/store_membership.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/enums/store_role.dart';
import 'package:electrical_parts_store_v2/features/dashboard/presentation/dashboard_page.dart';
import 'package:electrical_parts_store_v2/features/inventory/domain/entities/product.dart';
import 'package:electrical_parts_store_v2/features/inventory/domain/repositories/product_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Balance implements AccountingQueryRepository {
  final requests = <String>[];
  final delayed = <String, Completer<Result<TrialBalance>>>{};

  @override
  Future<Result<TrialBalance>> getTrialBalance({
    required StoreContext context,
  }) {
    requests.add(context.storeId);
    return delayed[context.storeId]?.future ??
        Future.value(Success(TrialBalance(lines: const [])));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Stock implements ProductRepository {
  final requests = <String>[];

  @override
  Future<Result<List<Product>>> getProducts({
    required StoreContext context,
    bool includeInactive = false,
  }) {
    requests.add(context.storeId);
    return Future.value(const Success<List<Product>>([]));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _screen(_Balance accounting, _Stock products, String store) {
  return MaterialApp(
    home: Scaffold(
      body: DashboardPage(
        key: const ValueKey('dashboard'),
        accountingQueryRepository: accounting,
        productRepository: products,
        user: const AuthenticatedUser(
          id: 'user-1',
          email: 'user@example.com',
        ),
        membership: StoreMembership(
          storeId: store,
          userId: 'user-1',
          role: StoreRole.owner,
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('old tenant finance responses cannot replace current dashboard',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 920));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final accounting = _Balance();
    final products = _Stock();
    accounting.delayed['store-a'] = Completer<Result<TrialBalance>>();
    await tester.pumpWidget(_screen(accounting, products, 'store-a'));
    await tester.pump();
    await tester.pumpWidget(_screen(accounting, products, 'store-b'));
    await tester.pumpAndSettle();

    expect(find.textContaining('المتجر: store-b'), findsOneWidget);
    expect(find.textContaining('ميزان المراجعة متوازن'), findsOneWidget);
    expect(products.requests, ['store-b']);

    accounting.delayed['store-a']!.complete(
      Success(TrialBalance(lines: const [])),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('المتجر: store-b'), findsOneWidget);
    expect(find.textContaining('المتجر: store-a'), findsNothing);
    expect(products.requests, ['store-b']);
  });
}
