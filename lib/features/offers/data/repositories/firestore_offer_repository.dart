import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' as firebase_functions;

import '../../../../core/commands/command_queue_repository.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../../infrastructure/firebase/firebase_paths.dart';
import '../../../../infrastructure/queue/cloud_function_queue_fallback.dart';
import '../../../sales/domain/entities/sale_posting_plan.dart';
import '../../../sales/domain/enums/sale_payment_method.dart';
import '../../domain/entities/offer.dart';
import '../../domain/entities/offer_order.dart';
import '../../domain/entities/offer_order_confirmation.dart';
import '../../domain/repositories/offer_repository.dart';
import '../mappers/offer_command_mapper.dart';
import '../mappers/offer_firestore_mapper.dart';

class FirestoreOfferRepository implements OfferRepository {
  FirestoreOfferRepository({
    required FirebaseFirestore firestore,
    required firebase_functions.FirebaseFunctions functions,
    CommandQueueRepository? commandQueue,
  })  : _firestore = firestore,
        _functions = functions,
        _commandQueue = commandQueue;

  final FirebaseFirestore _firestore;
  final firebase_functions.FirebaseFunctions _functions;
  final CommandQueueRepository? _commandQueue;

  @override
  Future<Result<List<Offer>>> getOffers({
    required StoreContext context,
    bool includeInactive = true,
  }) async {
    try {
      final snapshot =
          await FirebasePaths.offers(_firestore, context.storeId).get();
      final offers = snapshot.docs
          .map(OfferFirestoreMapper.fromSnapshot)
          .where((offer) =>
              offer.storeId == context.storeId &&
              (includeInactive || offer.isActive))
          .toList()
        ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
      return Success<List<Offer>>(offers);
    } on FirebaseException catch (error) {
      return FailureResult<List<Offer>>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<List<Offer>>(
          InfrastructureFailure(error.toString()));
    }
  }

  @override
  Future<Result<Offer>> createOffer({
    required StoreContext context,
    required Offer offer,
  }) async {
    if (offer.storeId != context.storeId) {
      return const FailureResult<Offer>(
        AuthorizationFailure('Offer does not belong to the active store.'),
      );
    }
    final payload = OfferCommandMapper.createOfferRequest(offer);
    try {
      final response = await _functions
          .httpsCallable('createOffer')
          .call<Map<String, dynamic>>(payload);
      if (response.data['offerId'] != offer.id) {
        return const FailureResult<Offer>(
          InfrastructureFailure('The offer service returned another id.'),
        );
      }
      return Success<Offer>(offer);
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      final queued = await _enqueueIfTransient(
        error: error,
        context: context,
        commandId: 'offer-${offer.id}',
        operation: 'createOffer',
        idempotencyKey: offer.id,
        payload: payload,
      );
      if (queued != null) {
        return FailureResult<Offer>(queued);
      }
      return FailureResult<Offer>(_mapFailure(error));
    } catch (error) {
      return FailureResult<Offer>(InfrastructureFailure(error.toString()));
    }
  }

  @override
  Future<Result<void>> updateOffer({
    required StoreContext context,
    required Offer offer,
  }) async {
    final payload = OfferCommandMapper.updateOfferRequest(offer);
    return _callVoid(
      context: context,
      commandId: 'update-offer-${offer.id}',
      operation: 'updateOffer',
      idempotencyKey: 'update-${offer.id}',
      payload: payload,
      functionName: 'updateOffer',
    );
  }

  @override
  Future<Result<void>> setOfferActive({
    required StoreContext context,
    required String offerId,
    required bool isActive,
  }) async {
    final payload = OfferCommandMapper.setActiveRequest(
      storeId: context.storeId,
      offerId: offerId,
      isActive: isActive,
    );
    return _callVoid(
      context: context,
      commandId: 'offer-active-$offerId-$isActive',
      operation: 'setOfferActive',
      idempotencyKey: 'offer-active-$offerId-$isActive',
      payload: payload,
      functionName: 'setOfferActive',
    );
  }

  @override
  Future<Result<void>> archiveOffer({
    required StoreContext context,
    required String offerId,
  }) async {
    final payload = OfferCommandMapper.archiveRequest(
      storeId: context.storeId,
      offerId: offerId,
    );
    return _callVoid(
      context: context,
      commandId: 'archive-offer-$offerId',
      operation: 'archiveOffer',
      idempotencyKey: 'archive-$offerId',
      payload: payload,
      functionName: 'archiveOffer',
    );
  }

  @override
  Future<Result<List<OfferOrder>>> getOfferOrders({
    required StoreContext context,
    String? offerId,
  }) async {
    try {
      final snapshot =
          await FirebasePaths.offerOrders(_firestore, context.storeId).get();
      final orders = snapshot.docs
          .map(OfferFirestoreMapper.orderFromSnapshot)
          .where((order) =>
              order.storeId == context.storeId &&
              (offerId == null || order.offerId == offerId))
          .toList()
        ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
      return Success<List<OfferOrder>>(orders);
    } on FirebaseException catch (error) {
      return FailureResult<List<OfferOrder>>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<List<OfferOrder>>(
          InfrastructureFailure(error.toString()));
    }
  }

  @override
  Future<Result<OfferOrder>> createOfferOrder({
    required StoreContext context,
    required OfferOrder order,
  }) async {
    final payload = OfferCommandMapper.createOrderRequest(order);
    try {
      final response = await _functions
          .httpsCallable('createOfferOrder')
          .call<Map<String, dynamic>>(payload);
      if (response.data['orderId'] != order.id) {
        return const FailureResult<OfferOrder>(
          InfrastructureFailure('The offer order service returned another id.'),
        );
      }
      return Success<OfferOrder>(order);
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      final queued = await _enqueueIfTransient(
        error: error,
        context: context,
        commandId: 'offer-order-${order.id}',
        operation: 'createOfferOrder',
        idempotencyKey: order.idempotencyKey.value,
        payload: payload,
      );
      if (queued != null) {
        return FailureResult<OfferOrder>(queued);
      }
      return FailureResult<OfferOrder>(_mapFailure(error));
    } catch (error) {
      return FailureResult<OfferOrder>(InfrastructureFailure(error.toString()));
    }
  }

  @override
  Future<Result<OfferOrderConfirmation>> confirmOfferOrder({
    required StoreContext context,
    required OfferOrder order,
    required SalePaymentMethod paymentMethod,
    required SalePostingAccounts accounts,
  }) async {
    final payload = OfferCommandMapper.confirmOrderRequest(
      order: order,
      paymentMethod: paymentMethod,
      accounts: accounts,
    );
    try {
      final response = await _functions
          .httpsCallable('confirmOfferOrder')
          .call<Map<String, dynamic>>(payload);
      final data = response.data;
      return Success<OfferOrderConfirmation>(
        OfferOrderConfirmation(
          orderId: order.id,
          saleId: data['saleId'] as String? ?? '',
          journalEntryId: data['journalEntryId'] as String? ?? '',
        ),
      );
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      final queued = await _enqueueIfTransient(
        error: error,
        context: context,
        commandId: 'confirm-offer-order-${order.id}',
        operation: 'confirmOfferOrder',
        idempotencyKey: 'confirm-${order.id}',
        payload: payload,
      );
      if (queued != null) {
        return FailureResult<OfferOrderConfirmation>(queued);
      }
      return FailureResult<OfferOrderConfirmation>(_mapFailure(error));
    } catch (error) {
      return FailureResult<OfferOrderConfirmation>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<void>> cancelOfferOrder({
    required StoreContext context,
    required String orderId,
  }) async {
    final payload = OfferCommandMapper.cancelOrderRequest(
      storeId: context.storeId,
      orderId: orderId,
    );
    return _callVoid(
      context: context,
      commandId: 'cancel-offer-order-$orderId',
      operation: 'cancelOfferOrder',
      idempotencyKey: 'cancel-$orderId',
      payload: payload,
      functionName: 'cancelOfferOrder',
    );
  }

  Future<Result<void>> _callVoid({
    required StoreContext context,
    required String commandId,
    required String operation,
    required String idempotencyKey,
    required Map<String, dynamic> payload,
    required String functionName,
  }) async {
    try {
      await _functions
          .httpsCallable(functionName)
          .call<Map<String, dynamic>>(payload);
      return const Success<void>(null);
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      final queued = await _enqueueIfTransient(
        error: error,
        context: context,
        commandId: commandId,
        operation: operation,
        idempotencyKey: idempotencyKey,
        payload: payload,
      );
      if (queued != null) {
        return FailureResult<void>(queued);
      }
      return FailureResult<void>(_mapFailure(error));
    } catch (error) {
      return FailureResult<void>(InfrastructureFailure(error.toString()));
    }
  }

  Future<Failure?> _enqueueIfTransient({
    required firebase_functions.FirebaseFunctionsException error,
    required StoreContext context,
    required String commandId,
    required String operation,
    required String idempotencyKey,
    required Map<String, dynamic> payload,
  }) async {
    final commandQueue = _commandQueue;
    if (commandQueue == null ||
        !CloudFunctionQueueFallback.isTransient(error)) {
      return null;
    }
    final queueFailure = await CloudFunctionQueueFallback.enqueue(
      repository: commandQueue,
      context: context,
      commandId: commandId,
      operation: operation,
      idempotencyKey: idempotencyKey,
      payload: payload,
    );
    if (queueFailure != null) {
      return queueFailure;
    }
    return QueuedFailure(commandId: commandId);
  }

  Failure _mapFailure(
    firebase_functions.FirebaseFunctionsException error,
  ) {
    switch (error.code) {
      case 'permission-denied':
      case 'unauthenticated':
        return AuthorizationFailure(
          error.message ?? 'Operation is not authorized.',
        );
      case 'invalid-argument':
      case 'failed-precondition':
        return ValidationFailure(
          error.message ?? 'Offer operation is invalid.',
        );
      case 'already-exists':
      case 'aborted':
        return ConflictFailure(
          error.message ?? 'Offer operation conflicts with existing data.',
        );
      default:
        return InfrastructureFailure(error.message ?? error.code);
    }
  }
}
