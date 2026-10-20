import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' as firebase_functions;

import '../../../../core/commands/command_queue_repository.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../../infrastructure/firebase/firebase_paths.dart';
import '../../../../infrastructure/queue/cloud_function_queue_fallback.dart';
import '../../domain/entities/repair_payment.dart';
import '../../domain/entities/repair_posting_accounts.dart';
import '../../domain/entities/repair_request.dart';
import '../../domain/enums/repair_status.dart';
import '../../domain/repositories/repair_repository.dart';
import '../mappers/repair_command_mapper.dart';
import '../mappers/repair_firestore_mapper.dart';

class FirestoreRepairRepository implements RepairRepository {
  FirestoreRepairRepository({
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
  Future<Result<List<RepairRequest>>> getRepairs({
    required StoreContext context,
    RepairStatus? status,
  }) async {
    try {
      Query<Map<String, dynamic>> query = FirebasePaths.repairs(
        _firestore,
        context.storeId,
      );
      if (status != null) {
        query = query.where('status', isEqualTo: status.name);
      }
      final snapshot = await query.get();
      final repairs = snapshot.docs
          .map(RepairFirestoreMapper.requestFromSnapshot)
          .where((repair) => repair.storeId == context.storeId)
          .toList()
        ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
      return Success<List<RepairRequest>>(repairs);
    } on FirebaseException catch (error) {
      return FailureResult<List<RepairRequest>>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<List<RepairRequest>>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<RepairRequest>> getRepair({
    required StoreContext context,
    required String repairId,
  }) async {
    if (repairId.trim().isEmpty || repairId.contains('/')) {
      return const FailureResult<RepairRequest>(
        ValidationFailure('Repair id is invalid.'),
      );
    }

    try {
      final snapshot = await FirebasePaths.repairs(
        _firestore,
        context.storeId,
      ).doc(repairId).get();
      if (!snapshot.exists) {
        return const FailureResult<RepairRequest>(
          ValidationFailure('Repair request was not found.'),
        );
      }
      final repair = RepairFirestoreMapper.requestFromSnapshot(snapshot);
      if (repair.storeId != context.storeId) {
        return const FailureResult<RepairRequest>(
          AuthorizationFailure('Repair belongs to another store.'),
        );
      }
      return Success<RepairRequest>(repair);
    } on FirebaseException catch (error) {
      return FailureResult<RepairRequest>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<RepairRequest>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<RepairRequest>> createRepair({
    required StoreContext context,
    required RepairRequest repair,
  }) async {
    if (repair.storeId != context.storeId) {
      return const FailureResult<RepairRequest>(
        AuthorizationFailure('Repair does not belong to the active store.'),
      );
    }
    final payload = RepairCommandMapper.createRequest(repair);
    try {
      final response = await _functions
          .httpsCallable('createRepair')
          .call<Map<String, dynamic>>(payload);
      if (response.data['repairId'] != repair.id) {
        return const FailureResult<RepairRequest>(
          InfrastructureFailure('The repair service returned another id.'),
        );
      }
      return Success<RepairRequest>(repair);
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      final queued = await _enqueueIfTransient(
        error: error,
        context: context,
        commandId: 'repair-${repair.id}',
        operation: 'createRepair',
        idempotencyKey: repair.idempotencyKey.value,
        payload: payload,
      );
      if (queued != null) {
        return FailureResult<RepairRequest>(queued);
      }
      return FailureResult<RepairRequest>(_mapFailure(error));
    } catch (error) {
      return FailureResult<RepairRequest>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<RepairRequest>> updateRepair({
    required StoreContext context,
    required RepairRequest repair,
  }) async {
    if (repair.storeId != context.storeId) {
      return const FailureResult<RepairRequest>(
        AuthorizationFailure('Repair does not belong to the active store.'),
      );
    }
    final payload = RepairCommandMapper.updateRequest(repair);
    try {
      final response = await _functions
          .httpsCallable('updateRepair')
          .call<Map<String, dynamic>>(payload);
      if (response.data['repairId'] != repair.id) {
        return const FailureResult<RepairRequest>(
          InfrastructureFailure('The repair update returned another id.'),
        );
      }
      return Success<RepairRequest>(repair);
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      final queued = await _enqueueIfTransient(
        error: error,
        context: context,
        commandId: 'update-repair-${repair.id}',
        operation: 'updateRepair',
        idempotencyKey: 'update-${repair.id}',
        payload: payload,
      );
      if (queued != null) {
        return FailureResult<RepairRequest>(queued);
      }
      return FailureResult<RepairRequest>(_mapFailure(error));
    } catch (error) {
      return FailureResult<RepairRequest>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<RepairRequest>> deliverRepair({
    required StoreContext context,
    required String repairId,
    required String idempotencyKey,
    required DateTime postedAt,
    required RepairPostingAccounts accounts,
  }) async {
    accounts.validate();
    final payload = RepairCommandMapper.deliverRequest(
      storeId: context.storeId,
      repairId: repairId,
      idempotencyKey: idempotencyKey,
      postedAt: postedAt,
      accounts: accounts,
    );
    try {
      final response = await _functions
          .httpsCallable('deliverRepair')
          .call<Map<String, dynamic>>(payload);
      if (response.data['repairId'] != repairId) {
        return const FailureResult<RepairRequest>(
          InfrastructureFailure('The delivery service returned another id.'),
        );
      }
      final current = await getRepair(context: context, repairId: repairId);
      if (current is Success<RepairRequest>) {
        return current;
      }
      return FailureResult<RepairRequest>(
        (current as FailureResult<RepairRequest>).failure,
      );
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      final queued = await _enqueueIfTransient(
        error: error,
        context: context,
        commandId: 'deliver-repair-$repairId',
        operation: 'deliverRepair',
        idempotencyKey: idempotencyKey,
        payload: payload,
      );
      if (queued != null) {
        return FailureResult<RepairRequest>(queued);
      }
      return FailureResult<RepairRequest>(_mapFailure(error));
    } catch (error) {
      return FailureResult<RepairRequest>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<RepairPayment>> postPayment({
    required StoreContext context,
    required RepairPayment payment,
    required RepairPostingAccounts accounts,
  }) async {
    if (payment.storeId != context.storeId) {
      return const FailureResult<RepairPayment>(
        AuthorizationFailure('Repair payment does not belong to the store.'),
      );
    }
    final payload = RepairCommandMapper.paymentRequest(
      payment: payment,
      accounts: accounts,
    );
    try {
      final response = await _functions
          .httpsCallable(
            payment.kind.name == 'advance'
                ? 'postRepairAdvance'
                : 'postRepairPayment',
          )
          .call<Map<String, dynamic>>(payload);
      if (response.data['paymentId'] != payment.id) {
        return const FailureResult<RepairPayment>(
          InfrastructureFailure('The repair payment returned another id.'),
        );
      }
      return Success<RepairPayment>(payment);
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      final operation = payment.kind.name == 'advance'
          ? 'postRepairAdvance'
          : 'postRepairPayment';
      final queued = await _enqueueIfTransient(
        error: error,
        context: context,
        commandId: 'repair-payment-${payment.id}',
        operation: operation,
        idempotencyKey: payment.idempotencyKey.value,
        payload: payload,
      );
      if (queued != null) {
        return FailureResult<RepairPayment>(queued);
      }
      return FailureResult<RepairPayment>(_mapFailure(error));
    } catch (error) {
      return FailureResult<RepairPayment>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<List<RepairPayment>>> getPayments({
    required StoreContext context,
    required String repairId,
  }) async {
    try {
      final snapshot = await FirebasePaths.repairPayments(
        _firestore,
        context.storeId,
      ).where('repairId', isEqualTo: repairId).get();
      final payments = snapshot.docs
          .map(RepairFirestoreMapper.paymentFromSnapshot)
          .where(
            (payment) =>
                payment.storeId == context.storeId &&
                payment.repairId == repairId,
          )
          .toList()
        ..sort((left, right) => right.postedAt.compareTo(left.postedAt));
      return Success<List<RepairPayment>>(payments);
    } on FirebaseException catch (error) {
      return FailureResult<List<RepairPayment>>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<List<RepairPayment>>(
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
    final queue = _commandQueue;
    if (queue == null || !CloudFunctionQueueFallback.isTransient(error)) {
      return null;
    }
    final queueFailure = await CloudFunctionQueueFallback.enqueue(
      repository: queue,
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
          error.message ?? 'Repair operation is not authorized.',
        );
      case 'invalid-argument':
      case 'failed-precondition':
        return ValidationFailure(
          error.message ?? 'Repair operation is invalid.',
        );
      case 'already-exists':
      case 'aborted':
        return ConflictFailure(
          error.message ?? 'Repair operation conflicts with existing data.',
        );
      default:
        return InfrastructureFailure(error.message ?? error.code);
    }
  }
}
