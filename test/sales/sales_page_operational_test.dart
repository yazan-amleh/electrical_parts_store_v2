import 'package:electrical_parts_store_v2/core/errors/failure.dart';
import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/core/quantity/quantity.dart';
import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/authenticated_user.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/store_membership.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/enums/store_role.dart';
import 'package:electrical_parts_store_v2/features/inventory/domain/entities/product.dart';
import 'package:electrical_parts_store_v2/features/inventory/domain/repositories/product_repository.dart';
import 'package:electrical_parts_store_v2/features/sales/domain/entities/sale.dart';
import 'package:electrical_parts_store_v2/features/sales/domain/entities/sale_posting_plan.dart';
import 'package:electrical_parts_store_v2/features/sales/domain/entities/sale_return.dart';
import 'package:electrical_parts_store_v2/features/sales/domain/repositories/sale_repository.dart';
import 'package:electrical_parts_store_v2/features/sales/presentation/sales_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Product product(
  String id,
  String currency, {
  String storeId = 'store-1',
  bool active = true,
}) {
  return Product(
    id: id,
    storeId: storeId,
    name: id,
    purchasePrice: Money(minorUnits: 500, currency: currency),
    sellingPrice: Money(minorUnits: 1000, currency: currency),
    wholesalePrice: Money(minorUnits: 850, currency: currency),
    quantityOnHand: const Quantity.fromMilliUnits(10000),
    minimumQuantity: const Quantity.fromMilliUnits(1000),
    categoryId: 'category-1',
    isActive: active,
  );
}

class _Products implements ProductRepository {
  _Products(this.items);
  final List<Product> items;

  @override
  Future<Result<List<Product>>> getProducts({
    required StoreContext context,
    bool includeInactive = false,
  }) async {
    return Success(items.where((e) => e.storeId == context.storeId).toList());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sales implements SaleRepository {
  final List<Sale> submissions = [];
  bool queued = false;

  @override
  Future<Result<SaleReturnPostingResult>> postFullSaleReturn({
    required StoreContext context,
    required SaleReturn saleReturn,
    required SaleReturnPostingAccounts accounts,
  }) async {
    return const FailureResult(
      InfrastructureFailure('Not used by point-of-sale tests'),
    );
  }

  @override
  Future<Result<SalePostingPlan>> postSale({
    required StoreContext context,
    required Sale sale,
    required SalePostingAccounts accounts,
  }) async {
    submissions.add(sale);
    if (queued) {
      return const FailureResult(
        QueuedFailure(commandId: 'queue-sale-1'),
      );
    }
    return const FailureResult(
      InfrastructureFailure('Connection interrupted'),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {});

  Widget screen(
    ProductRepository products,
    SaleRepository sales, {
    StoreRole role = StoreRole.owner,
    String storeId = 'store-1',
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SalesPage(
          repository: sales,
          productRepository: products,
          user:
              const AuthenticatedUser(id: 'user-1', email: 'test@example.com'),
          membership: StoreMembership(
            storeId: storeId,
            userId: 'user-1',
            role: role,
          ),
        ),
      ),
    );
  }

  testWidgets('inactive products stay hidden and mixed currencies are rejected',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final products = _Products([
      product('ILS item', 'ILS'),
      product('USD item', 'USD'),
      product('Inactive item', 'ILS', active: false),
    ]);
    await tester.pumpWidget(screen(products, _Sales()));
    await tester.pumpAndSettle();

    expect(find.text('Inactive item'), findsNothing);
    await tester.tap(find.text('ILS item'));
    await tester.pump();
    await tester.tap(find.text('USD item'));
    await tester.pump();

    expect(
        find.textContaining('لا يمكن بيع أصناف بعملات مختلفة'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.text('ILS item'), findsWidgets);
  });

  testWidgets(
      'unknown outcome retry uses exactly the same sale idempotency key',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final sales = _Sales();
    await tester.pumpWidget(screen(
      _Products([product('Cable', 'ILS')]),
      sales,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cable'));
    await tester.pump();

    await tester.tap(find.textContaining('ترحيل البيع'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('ترحيل البيع'));
    await tester.pumpAndSettle();

    expect(sales.submissions, hasLength(2));
    expect(sales.submissions.first.id, sales.submissions.last.id);
    expect(
      sales.submissions.first.idempotencyKey.value,
      sales.submissions.last.idempotencyKey.value,
    );
  });

  testWidgets('queued sales cannot be re-posted accidentally', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final sales = _Sales()..queued = true;
    await tester.pumpWidget(screen(
      _Products([product('Cable', 'ILS')]),
      sales,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cable'));
    await tester.pump();
    await tester.tap(find.textContaining('ترحيل البيع'));
    await tester.pumpAndSettle();
    expect(sales.submissions, hasLength(1));
    expect(find.text('البيع محفوظ في طابور الترحيل'), findsOneWidget);
    await tester.tap(find.byTooltip('تفريغ الفاتورة'));
    await tester.pumpAndSettle();
    expect(find.text('فاتورة في طابور الترحيل'), findsOneWidget);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(find.text('البيع محفوظ في طابور الترحيل'), findsOneWidget);
    expect(sales.submissions, hasLength(1));
  });

  testWidgets('non-sales user cannot access the point of sale', (tester) async {
    await tester.pumpWidget(screen(
      _Products([product('Cable', 'ILS')]),
      _Sales(),
      role: StoreRole.viewer,
    ));
    await tester.pumpAndSettle();
    expect(find.text('ليس لديك صلاحية لإنشاء المبيعات.'), findsOneWidget);
    expect(find.text('Cable'), findsNothing);
  });
}
