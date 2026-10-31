import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/offer.dart';
import '../entities/offer_order.dart';
import '../entities/offer_order_confirmation.dart';

abstract interface class OfferRepository {
  Future<Result<List<Offer>>> getOffers({
    required StoreContext context,
    bool includeInactive = true,
  });

  Future<Result<Offer>> createOffer({
    required StoreContext context,
    required Offer offer,
  });

  Future<Result<void>> updateOffer({
    required StoreContext context,
    required Offer offer,
  });

  Future<Result<void>> setOfferActive({
    required StoreContext context,
    required String offerId,
    required bool isActive,
  });

  Future<Result<void>> archiveOffer({
    required StoreContext context,
    required String offerId,
  });

  Future<Result<List<OfferOrder>>> getOfferOrders({
    required StoreContext context,
    String? offerId,
  });

  Future<Result<OfferOrder>> createOfferOrder({
    required StoreContext context,
    required OfferOrder order,
  });

  Future<Result<OfferOrderConfirmation>> confirmOfferOrder({
    required StoreContext context,
    required OfferOrder order,
    required OfferOrderConfirmationRequest confirmation,
  });

  Future<Result<void>> cancelOfferOrder({
    required StoreContext context,
    required String orderId,
  });
}
