import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' as firebase_functions;

import '../../../../core/commands/command_queue_repository.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../../infrastructure/firebase/firebase_paths.dart';
import '../../../../infrastructure/queue/cloud_function_queue_fallback.dart';
import '../../../purchases/domain/entities/purchase_posting_plan.dart';
import '../../../purchases/domain/enums/purchase_payment_method.dart';
import '../../domain/entities/purchase_order.dart';
import '../../domain/entities/purchase_order_receipt.dart';
import '../../domain/repositories/purchase_order_repository.dart';
import '../mappers/purchase_order_command_mapper.dart';
import '../mappers/purchase_order_firestore_mapper.dart';

class FirestorePurchaseOrderRepository implements PurchaseOrderRepository {
  FirestorePurchaseOrderRepository({
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
  Future<Result<List<PurchaseOrder>>> getPurchaseOrders({
    required StoreContext context,
  }) async {
    try {
      final snapshot = await FirebasePaths.purchaseOrders(
        _firestore,
        context.storeId,
      ).get();
      final orders = snapshot.docs
          .map(PurchaseOrderFirestoreMapper.fromSnapshot)
          .where((order) => order.storeId == context.storeId)
          .toList()
        ..sort((left, right) => right.orderedAt.compareTo(left.orderedAt));
      return Success<List<PurchaseOrder>>(orders);
    } on FirebaseException catch (error) {
      return FailureResult<List<PurchaseOrder>>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<List<PurchaseOrder>>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<PurchaseOrder>> createPurchaseOrder({
    required StoreContext context,
    required PurchaseOrder order,
  }) async {
    if (order.storeId != context.storeId) {
      return const FailureResult<PurchaseOrder>(
        AuthorizationFailure(
          'Purchase order does not belong to the active store.',
        ),
      );
    }

    final payload = PurchaseOrderCommandMapper.createRequest(order);
    try {
      final response = await _functions
          .httpsCallable('createPurchaseOrder')
          .call<Map<String, dynamic>>(payload);
      if (response.data['orderId'] != order.id) {
        return const FailureResult<PurchaseOrder>(
          InfrastructureFailure('The order service returned another order id.'),
        );
      }
      return Success<PurchaseOrder>(order);
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      final queued = await _enqueueIfTransient(
        error: error,
        context: context,
        commandId: 'purchase-order-${order.id}',
        operation: 'createPurchaseOrder',
        idempotencyKey: order.id,
        payload: payload,
      );
      if (queued != null) {
        return FailureResult<PurchaseOrder>(queued);
      }
      return FailureResult<PurchaseOrder>(_mapFailure(error));
    } catch (error) {
      return FailureResult<PurchaseOrder>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<void>> cancelPurchaseOrder({
    required StoreContext context,
    required String orderId,
  }) async {
    final payload = PurchaseOrderCommandMapper.cancelRequest(
      storeId: context.storeId,
      orderId: orderId,
    );
    try {
      await _functions
          .httpsCallable('cancelPurchaseOrder')
          .call<Map<String, dynamic>>(payload);
      return const Success<void>(null);
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      final queued = await _enqueueIfTransient(
        error: error,
        context: context,
        commandId: 'cancel-purchase-order-$orderId',
        operation: 'cancelPurchaseOrder',
        idempotencyKey: 'cancel-$orderId',
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

  @override
  Future<Result<PurchaseOrderReceipt>> receivePurchaseOrder({
    required StoreContext context,
    required PurchaseOrder order,
    required PurchaseOrderReceiptRequest receipt,
    required PurchasePaymentMethod paymentMethod,
    required PurchasePostingAccounts accounts,
    required int taxMinorUnits,
  }) async {
    final payload = PurchaseOrderCommandMapper.receiveRequest(
      order: order,
      receipt: receipt,
      paymentMethod: paymentMethod,
      accounts: accounts,
      taxMinorUnits: taxMinorUnits,
    );
    try {
      final response = await _functions
          .httpsCallable('receivePurchaseOrder')
          .call<Map<String, dynamic>>(payload);
      final data = response.data;
      final orderStatus = data['orderStatus'];
      final completed = data['completed'];
      if (data['purchaseId'] is! String ||
          data['journalEntryId'] is! String ||
          orderStatus is! String ||
          completed is! bool ||
          (orderStatus != 'pending' && orderStatus != 'completed')) {
        return const FailureResult<PurchaseOrderReceipt>(
          InfrastructureFailure(
            'The receipt service returned inconsistent data.',
          ),
        );
      }
      return Success<PurchaseOrderReceipt>(
        PurchaseOrderReceipt(
          orderId: order.id,
          purchaseId: data['purchaseId'] as String,
          journalEntryId: data['journalEntryId'] as String,
          completed: completed,
          orderStatus: orderStatus,
        ),
      );
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      final queued = await _enqueueIfTransient(
        error: error,
        context: context,
        commandId: 'receive-purchase-order-${order.id}',
        operation: 'receivePurchaseOrder',
        idempotencyKey: receipt.idempotencyKey.value,
        payload: payload,
      );
      if (queued != null) {
        return FailureResult<PurchaseOrderReceipt>(queued);
      }
      return FailureResult<PurchaseOrderReceipt>(_mapFailure(error));
    } catch (error) {
      return FailureResult<PurchaseOrderReceipt>(
        InfrastructureFailure(error.toString()),
      );
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

  Failure _mapFailure(firebase_functions.FirebaseFunctionsException error) {
    switch (error.code) {
      case 'permission-denied':
      case 'unauthenticated':
        return AuthorizationFailure(
          error.message ?? 'Operation is not authorized.',
        );
      case 'invalid-argument':
      case 'failed-precondition':
        return ValidationFailure(error.message ?? 'Purchase order is invalid.');
      case 'already-exists':
      case 'aborted':
        return ConflictFailure(
          error.message ?? 'Purchase order conflicts with existing data.',
        );
      default:
        return InfrastructureFailure(error.message ?? error.code);
    }
  }
}
