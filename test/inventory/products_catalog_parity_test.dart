import 'dart:async';

import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/core/quantity/quantity.dart';
import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/authenticated_user.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/store_membership.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/enums/store_role.dart';
import 'package:electrical_parts_store_v2/features/categories/domain/entities/category.dart';
import 'package:electrical_parts_store_v2/features/categories/domain/repositories/category_repository.dart';
import 'package:electrical_parts_store_v2/features/inventory/domain/entities/product.dart';
import 'package:electrical_parts_store_v2/features/inventory/domain/repositories/product_repository.dart';
import 'package:electrical_parts_store_v2/features/inventory/presentation/products_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Product _part(
  String id,
  String name,
  int milliUnits, {
  String storeId = 'store-a',
  String currency = 'ILS',
  int price = 1000,
  bool isService = false,
}) =>
    Product(
      id: id,
      storeId: storeId,
      name: name,
      purchasePrice: Money(minorUnits: 200, currency: currency),
      sellingPrice: Money(minorUnits: price, currency: currency),
      wholesalePrice: Money(minorUnits: 800, currency: currency),
      quantityOnHand: Quantity.fromMilliUnits(milliUnits),
      minimumQuantity: const Quantity.fromMilliUnits(2000),
      categoryId: 'category-1',
      isService: isService,
    );

class _Catalog implements ProductRepository {
  final calls = <String>[];
  final completers = <String, Completer<Result<List<Product>>>>{};
  List<Product> fixed = [];

  @override
  Future<Result<List<Product>>> getProducts({
    required StoreContext context,
    bool includeInactive = false,
  }) {
    calls.add(context.storeId);
    final pending = completers[context.storeId];
    if (pending != null) return pending.future;
    return Future.value(Success(fixed));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CategorySource implements CategoryRepository {
  final pending = <String, Completer<Result<List<Category>>>>{};

  @override
  Future<Result<List<Category>>> getCategories({
    required StoreContext context,
    bool includeInactive = false,
  }) {
    final delayed = pending[context.storeId];
    if (delayed != null) return delayed.future;
    return Future.value(Success(<Category>[
      Category(
        id: 'category-1',
        storeId: context.storeId,
        name: 'عام',
      ),
    ]));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _screen(
  _Catalog repo,
  String storeId, {
  CategoryRepository? categories,
}) =>
    MaterialApp(
      home: Scaffold(
        body: ProductsPage(
          key: const ValueKey('catalog'),
          repository: repo,
          categoryRepository: categories,
          user: const AuthenticatedUser(
            id: 'user-1',
            email: 'test@example.com',
          ),
          membership: StoreMembership(
            storeId: storeId,
            userId: 'user-1',
            role: StoreRole.owner,
          ),
        ),
      ),
    );

void main() {
  testWidgets('V1 catalog parity: sorted stock and honest per-currency stats',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1250, 920));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = _Catalog()
      ..fixed = [
        _part('z', 'زيتونة', 7000, price: 2300),
        _part('a', 'أسلاك', 1000, price: 1200),
        _part('c', 'محول', 4000, currency: 'USD'),
        _part('s', 'تصليح', 0, isService: true),
      ];
    await tester.pumpWidget(_screen(repo, 'store-a', categories: _CategorySource()));
    await tester.pumpAndSettle();
    expect(find.text('أصناف نشطة: 4'), findsOneWidget);
    expect(find.text('خدمات: 1'), findsOneWidget);
    expect(find.text('أصناف منخفضة: 1'), findsOneWidget);
    expect(find.textContaining('قيمة المخزون المحمّل — ILS'), findsOneWidget);
    expect(find.textContaining('قيمة المخزون المحمّل — USD'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('products-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الأقل مخزونًا').last);
    await tester.pumpAndSettle();
    final positions = <String, double>{};
    for (final name in ['أسلاك', 'محول', 'زيتونة']) {
      positions[name] = tester.getTopLeft(find.text(name)).dy;
    }
    expect(positions['أسلاك']!, lessThan(positions['محول']!));
    expect(positions['محول']!, lessThan(positions['زيتونة']!));

    await tester.tap(find.text('منخفض المخزون'));
    await tester.pumpAndSettle();
    expect(find.text('أسلاك'), findsOneWidget);
    expect(find.text('زيتونة'), findsNothing);
    expect(find.textContaining('مطابق للفلاتر: 1'), findsOneWidget);
  });

  testWidgets('late catalog response for old store cannot overwrite new tenant',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = _Catalog();
    repo.completers['store-a'] = Completer<Result<List<Product>>>();
    repo.completers['store-b'] = Completer<Result<List<Product>>>();
    await tester.pumpWidget(_screen(repo, 'store-a'));
    await tester.pump();
    await tester.pumpWidget(_screen(repo, 'store-b'));
    await tester.pump();
    repo.completers['store-b']!.complete(
      Success([_part('b', 'منتج المتجر ب', 5000, storeId: 'store-b')]),
    );
    await tester.pumpAndSettle();
    expect(find.text('منتج المتجر ب'), findsOneWidget);
    repo.completers['store-a']!.complete(
      Success([_part('a', 'منتج المتجر أ', 5000)]),
    );
    await tester.pumpAndSettle();
    expect(find.text('منتج المتجر أ'), findsNothing);
    expect(find.text('منتج المتجر ب'), findsOneWidget);
    expect(repo.calls, ['store-a', 'store-b']);
  });

  testWidgets('refuses a mismatched store document before displaying it',
      (tester) async {
    final repo = _Catalog()
      ..fixed = [_part('cross', 'سرية متجر آخر', 2000, storeId: 'store-b')];
    await tester.pumpWidget(_screen(repo, 'store-a'));
    await tester.pumpAndSettle();
    expect(find.text('سرية متجر آخر'), findsNothing);
    expect(find.textContaining('تم رفض تحميلها'), findsOneWidget);
  });
}
