import 'package:electrical_parts_store_v2/core/errors/failure.dart';
import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/core/quantity/quantity.dart';
import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/authenticated_user.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/store_membership.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/enums/store_role.dart';
import 'package:electrical_parts_store_v2/features/offers/domain/entities/offer.dart';
import 'package:electrical_parts_store_v2/features/offers/domain/entities/offer_line.dart';
import 'package:electrical_parts_store_v2/features/offers/domain/entities/offer_order.dart';
import 'package:electrical_parts_store_v2/features/offers/domain/entities/offer_order_confirmation.dart';
import 'package:electrical_parts_store_v2/features/offers/domain/enums/offer_order_status.dart';
import 'package:electrical_parts_store_v2/features/offers/domain/enums/offer_price_type.dart';
import 'package:electrical_parts_store_v2/features/offers/domain/repositories/offer_repository.dart';
import 'package:electrical_parts_store_v2/features/offers/presentation/offers_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Offers implements OfferRepository {
  final confirmations = <OfferOrderConfirmationRequest>[];

  OfferOrder get order => OfferOrder(
        id: 'order-1',
        storeId: 'store-1',
        orderNumber: 'OO-1',
        offerId: 'offer-1',
        offerNumber: 'OFFER-1',
        customerId: 'customer-1',
        customerName: 'Customer',
        lines: [
          OfferLine(
            id: 'line-1',
            productId: 'product-1',
            productName: 'Cable',
            originalUnitPrice: const Money(minorUnits: 1000),
            finalUnitPrice: const Money(minorUnits: 900),
            quantity: const Quantity.fromMilliUnits(1000),
            unitFactorToBase: const Quantity.fromMilliUnits(1000),
            priceType: OfferPriceType.retail,
          ),
        ],
        createdAt: DateTime.utc(2026, 10, 29),
        status: OfferOrderStatus.pending,
      );

  @override
  Future<Result<List<Offer>>> getOffers({
    required StoreContext context,
    bool includeInactive = true,
  }) async {
    return const Success<List<Offer>>(<Offer>[]);
  }

  @override
  Future<Result<List<OfferOrder>>> getOfferOrders({
    required StoreContext context,
    String? offerId,
  }) async {
    return Success<List<OfferOrder>>(<OfferOrder>[order]);
  }

  @override
  Future<Result<OfferOrderConfirmation>> confirmOfferOrder({
    required StoreContext context,
    required OfferOrder order,
    required OfferOrderConfirmationRequest confirmation,
  }) async {
    confirmations.add(confirmation);
    if (confirmations.length == 1) {
      return const FailureResult<OfferOrderConfirmation>(
        InfrastructureFailure('Unknown network outcome'),
      );
    }
    return Success<OfferOrderConfirmation>(
      OfferOrderConfirmation(
        orderId: order.id,
        saleId: 'sale-offer-order-order-1',
        journalEntryId: 'sale-offer-order-order-1-journal',
        alreadyConfirmed: true,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('unknown offer confirmation retries the exact same request',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _Offers();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OffersPage(
            repository: repository,
            productRepository: null,
            partyRepository: null,
            user: const AuthenticatedUser(
              id: 'user-1',
              email: 'test@example.com',
            ),
            membership: const StoreMembership(
              storeId: 'store-1',
              userId: 'user-1',
              role: StoreRole.owner,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('الطلبات'));
    await tester.pumpAndSettle();
    expect(find.textContaining('OO-1'), findsOneWidget);

    await tester.tap(find.byTooltip('تأكيد وترحيل'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('نقدي'));
    await tester.pumpAndSettle();

    expect(repository.confirmations, hasLength(1));
    final first = repository.confirmations.single;
    expect(find.byTooltip('إعادة نفس التأكيد'), findsOneWidget);
    expect(
      find.byTooltip('لا يمكن الإلغاء قبل حسم التأكيد المعلق'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('إعادة نفس التأكيد'));
    await tester.pumpAndSettle();

    expect(repository.confirmations, hasLength(2));
    final second = repository.confirmations.last;
    expect(identical(first, second), isTrue);
    expect(second.idempotencyKey.value, first.idempotencyKey.value);
    expect(second.postedAt, first.postedAt);
    expect(second.paymentMethod, first.paymentMethod);
    expect(
      second.accounts.settlementAccountId,
      first.accounts.settlementAccountId,
    );
  });
}
