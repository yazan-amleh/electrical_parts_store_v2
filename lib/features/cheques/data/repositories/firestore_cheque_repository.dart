import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' as firebase_functions;

import '../../../../core/commands/command_queue_repository.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../../infrastructure/firebase/firebase_paths.dart';
import '../../../../infrastructure/queue/cloud_function_queue_fallback.dart';
import '../../domain/entities/cheque.dart';
import '../../domain/entities/cheque_settlement_request.dart';
import '../../domain/entities/cheque_settlement_result.dart';
import '../../domain/enums/cheque_settlement_action.dart';
import '../../domain/enums/cheque_status.dart';
import '../../domain/repositories/cheque_repository.dart';
import '../mappers/cheque_firestore_mapper.dart';

class FirestoreChequeRepository implements ChequeRepository {
  FirestoreChequeRepository({
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
  Future<Result<List<Cheque>>> getCheques({
    required StoreContext context,
    ChequeStatus? status,
  }) async {
    try {
      final snapshot = await FirebasePaths.partyPayments(
        _firestore,
        context.storeId,
      ).where('paymentMethod', isEqualTo: 'cheque').limit(500).get();
      final cheques = snapshot.docs
          .map(ChequeFirestoreMapper.fromSnapshot)
          .where(
            (cheque) =>
                cheque.storeId == context.storeId &&
                (status == null || cheque.status == status),
          )
          .toList()
        ..sort(
          (left, right) => right.receivedAt.compareTo(left.receivedAt),
        );
      return Success<List<Cheque>>(cheques);
    } on FirebaseException catch (error) {
      return FailureResult<List<Cheque>>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<List<Cheque>>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<ChequeSettlementResult>> settleCheque({
    required StoreContext context,
    required ChequeSettlementRequest request,
  }) async {
    final chequeId = request.chequeId;
    final action = request.action;
    final bankAccountId = request.bankAccountId;
    final idempotencyKey = request.idempotencyKey.value;
    final payload = <String, dynamic>{
      'storeId': context.storeId,
      'chequeId': chequeId,
      'action': action.name,
      'idempotencyKey': idempotencyKey,
      'postedAt': request.postedAt.toIso8601String(),
      'accounts': <String, dynamic>{
        'checksAccountId': '1130',
        'issuedChecksAccountId': '2210',
        'customerReceivableAccountId': '1140',
        'supplierPayableAccountId': '2110',
        'bankAccountId': bankAccountId,
      },
    };

    try {
      final callable = _functions.httpsCallable('settleCheque');
      final response = await callable.call<Map<String, dynamic>>(payload);
      final data = response.data;
      final statusName = data['status'];
      final journalEntryId = data['journalEntryId'];
      if (statusName is! String || journalEntryId is! String) {
        return const FailureResult<ChequeSettlementResult>(
          InfrastructureFailure(
            'The cheque settlement service returned inconsistent data.',
          ),
        );
      }
      final status = ChequeStatus.values.firstWhere(
        (candidate) => candidate.name == statusName,
        orElse: () => ChequeStatus.pending,
      );
      if (status == ChequeStatus.pending) {
        return const FailureResult<ChequeSettlementResult>(
          InfrastructureFailure(
            'The cheque settlement service returned an invalid status.',
          ),
        );
      }
      return Success<ChequeSettlementResult>(
        ChequeSettlementResult(
          chequeId: chequeId,
          status: status,
          journalEntryId: journalEntryId,
        ),
      );
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      if (_commandQueue != null &&
          CloudFunctionQueueFallback.isTransient(error)) {
        final commandId = 'settle-cheque-$chequeId-${action.name}';
        final queueFailure = await CloudFunctionQueueFallback.enqueue(
          repository: _commandQueue,
          context: context,
          commandId: commandId,
          operation: 'settleCheque',
          idempotencyKey: idempotencyKey,
          payload: payload,
        );
        if (queueFailure != null) {
          return FailureResult<ChequeSettlementResult>(queueFailure);
        }
        return FailureResult<ChequeSettlementResult>(
          QueuedFailure(commandId: commandId),
        );
      }
      return FailureResult<ChequeSettlementResult>(_mapFailure(error));
    } catch (error) {
      return FailureResult<ChequeSettlementResult>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  Failure _mapFailure(firebase_functions.FirebaseFunctionsException error) {
    switch (error.code) {
      case 'permission-denied':
      case 'unauthenticated':
        return AuthorizationFailure(
          error.message ?? 'Cheque settlement is not authorized.',
        );
      case 'invalid-argument':
      case 'failed-precondition':
        return ValidationFailure(
          error.message ?? 'Cheque settlement is invalid.',
        );
      case 'already-exists':
      case 'aborted':
        return ConflictFailure(
          error.message ?? 'Cheque settlement conflicts with existing data.',
        );
      default:
        return InfrastructureFailure(error.message ?? error.code);
    }
  }
}
