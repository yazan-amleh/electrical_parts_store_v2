import 'package:electrical_parts_store_v2/core/errors/failure.dart';
import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/authenticated_user.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/store_membership.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/enums/store_role.dart';
import 'package:electrical_parts_store_v2/features/purchases/domain/entities/purchase_invoice.dart';
import 'package:electrical_parts_store_v2/features/purchases/domain/entities/purchase_return.dart';
import 'package:electrical_parts_store_v2/features/purchases/domain/repositories/purchase_repository.dart';
import 'package:electrical_parts_store_v2/features/purchases/presentation/purchase_returns_panel.dart';
import 'package:electrical_parts_store_v2/features/purchases/presentation/purchases_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _PurchaseReturnsRepository implements PurchaseRepository {
  _PurchaseReturnsRepository({this.failFirst = false});

  final bool failFirst;
  final submissions = <PurchaseReturn>[];

  PurchaseInvoiceSummary get invoice => PurchaseInvoiceSummary(
        id: 'purchase-100',
        storeId: 'store-1',
        postedAt: DateTime.utc(2026, 10, 27),
        paymentMethod: 'cash',
        subtotal: const Money(minorUnits: 10000),
        tax: const Money(minorUnits: 1600),
        total: const Money(minorUnits: 11600),
        journalEntryId: 'purchase-100-journal',
      );

  PurchaseInvoiceDocument get document => PurchaseInvoiceDocument(
        invoice: invoice,
        lines: const [
          PurchaseInvoiceLineSummary(
            id: 'line-1',
            productId: 'product-1',
            description: 'كابل',
            quantityMilliUnits: 2000,
            baseQuantityMilliUnits: 2000,
            unitCost: Money(minorUnits: 5000),
            discount: Money(minorUnits: 0),
            total: Money(minorUnits: 10000),
            returnedQuantityMilliUnits: 500,
            unitName: 'متر',
          ),
        ],
      );

  @override
  Future<Result<List<PurchaseInvoiceSummary>>> getRecentPurchaseInvoices({
    required StoreContext context,
    int limit = 100,
  }) async {
    return Success(<PurchaseInvoiceSummary>[invoice]);
  }

  @override
  Future<Result<PurchaseInvoiceDocument>> getPurchaseInvoiceDocument({
    required StoreContext context,
    required String purchaseId,
  }) async {
    return Success(document);
  }

  @override
  Future<Result<PurchaseReturnPostingResult>> postPurchaseReturn({
    required StoreContext context,
    required PurchaseReturn purchaseReturn,
    required PurchaseReturnPostingAccounts accounts,
  }) async {
    submissions.add(purchaseReturn);
    if (failFirst && submissions.length == 1) {
      return const FailureResult<PurchaseReturnPostingResult>(
        InfrastructureFailure('Unknown network outcome'),
      );
    }
    return Success(
      PurchaseReturnPostingResult(
        returnId: purchaseReturn.id,
        originalPurchaseId: purchaseReturn.originalPurchaseId,
        journalEntryId: '${purchaseReturn.id}-journal',
        alreadyReturned: false,
        inventoryCarryingValueMinorUnits: 2500,
        valuationVarianceMinorUnits: 0,
        returnStatus: purchaseReturn.lines == null ? 'full' : 'partial',
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _user = AuthenticatedUser(
  id: 'user-1',
  email: 'test@example.com',
);
const _membership = StoreMembership(
  storeId: 'store-1',
  userId: 'user-1',
  role: StoreRole.owner,
);

Widget _panel(_PurchaseReturnsRepository repository) {
  return MaterialApp(
    home: Scaffold(
      body: PurchaseReturnsPanel(
        repository: repository,
        user: _user,
        membership: _membership,
      ),
    ),
  );
}

void main() {
  testWidgets('purchases page exposes the purchase-return mode',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _PurchaseReturnsRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PurchasesPage(
            repository: repository,
            productRepository: null,
            user: _user,
            membership: _membership,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('شراء جديد'), findsOneWidget);
    expect(find.text('مردود مشتريات'), findsOneWidget);
    await tester.tap(find.text('مردود مشتريات'));
    await tester.pumpAndSettle();

    expect(find.text('فواتير الشراء'), findsOneWidget);
    expect(find.text('purchase-100'), findsOneWidget);
  });

  testWidgets(
      'partial purchase return submits only selected remaining quantity',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _PurchaseReturnsRepository();

    await tester.pumpWidget(_panel(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('purchase-100'));
    await tester.pumpAndSettle();

    expect(find.textContaining('المتبقي: 1.5'), findsOneWidget);
    await tester.tap(find.text('مردود جزئي'));
    await tester.pumpAndSettle();

    final quantity = find.byKey(
      const ValueKey('purchase-return-qty-line-1'),
    );
    expect(quantity, findsOneWidget);
    await tester.enterText(quantity, '0.5');
    await tester.tap(find.text('ترحيل المردود الجزئي'));
    await tester.pumpAndSettle();

    expect(repository.submissions, hasLength(1));
    final command = repository.submissions.single;
    expect(command.originalPurchaseId, 'purchase-100');
    expect(command.lines, isNotNull);
    expect(command.lines, hasLength(1));
    expect(command.lines!.single.lineId, 'line-1');
    expect(command.lines!.single.quantityMilliUnits, 500);
  });

  testWidgets('unknown purchase-return outcome retries the exact same command',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _PurchaseReturnsRepository(failFirst: true);

    await tester.pumpWidget(_panel(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('purchase-100'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مردود جزئي'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('purchase-return-qty-line-1')),
      '0.5',
    );
    await tester.tap(find.text('ترحيل المردود الجزئي'));
    await tester.pumpAndSettle();

    expect(repository.submissions, hasLength(1));
    final first = repository.submissions.single;
    expect(find.text('إعادة نفس الطلب'), findsOneWidget);

    await tester.tap(find.text('إعادة نفس الطلب'));
    await tester.pumpAndSettle();

    expect(repository.submissions, hasLength(2));
    final second = repository.submissions.last;
    expect(identical(first, second), isTrue);
    expect(second.id, first.id);
    expect(second.idempotencyKey.value, first.idempotencyKey.value);
    expect(second.postedAt, first.postedAt);
    expect(second.reason, first.reason);
    expect(
      second.lines!.single.quantityMilliUnits,
      first.lines!.single.quantityMilliUnits,
    );
  });
}
