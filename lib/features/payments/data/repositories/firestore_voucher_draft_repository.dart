import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' as cloud_functions;

import '../../../../core/errors/failure.dart';
import '../../../../core/money/money.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../../infrastructure/firebase/firebase_paths.dart';
import '../../../parties/domain/enums/party_type.dart';
import '../../domain/entities/party_payment.dart';
import '../../domain/entities/party_payment_posting_plan.dart';
import '../../domain/entities/voucher_draft.dart';
import '../../domain/repositories/voucher_draft_repository.dart';
import '../mappers/party_payment_command_mapper.dart';

class FirestoreVoucherDraftRepository implements VoucherDraftRepository {
  const FirestoreVoucherDraftRepository({
    required FirebaseFirestore firestore,
    required cloud_functions.FirebaseFunctions functions,
  })  : _firestore = firestore,
        _functions = functions;

  final FirebaseFirestore _firestore;
  final cloud_functions.FirebaseFunctions _functions;

  @override
  Future<Result<String>> saveDraft({
    required StoreContext context,
    required PartyPayment payment,
    required PartyPaymentPostingAccounts accounts,
  }) async {
    if (context.storeId != payment.storeId || context.userId.trim().isEmpty) {
      return const FailureResult<String>(
        ValidationFailure('Store or creator does not match this draft.'),
      );
    }
    try {
      final result = await _functions
          .httpsCallable('saveVoucherDraft')
          .call<Map<String, dynamic>>(
            PartyPaymentCommandMapper.toRequest(
              payment: payment,
              accounts: accounts,
            ),
          );
      final id = result.data['draftId'];
      if (id != payment.id) {
        return const FailureResult<String>(
          InfrastructureFailure('Draft service returned the wrong identifier.'),
        );
      }
      return Success<String>(id as String);
    } on cloud_functions.FirebaseFunctionsException catch (error) {
      return FailureResult<String>(_functionFailure(error));
    } catch (error) {
      return FailureResult<String>(InfrastructureFailure(error.toString()));
    }
  }

  @override
  Future<Result<void>> updateDraft({
    required StoreContext context,
    required String draftId,
    required int expectedRevision,
    required int amountMinorUnits,
    required String? description,
  }) {
    if (expectedRevision < 1 || amountMinorUnits <= 0 ||
        (description?.length ?? 0) > 500) {
      return Future.value(
        const FailureResult<void>(
          ValidationFailure('Invalid draft revision, amount, or description.'),
        ),
      );
    }
    return _action(
      'updateVoucherDraft',
      context,
      draftId,
      extra: {
        'expectedRevision': expectedRevision,
        'amountMinorUnits': amountMinorUnits,
        'description': description,
      },
    );
  }

  @override
  Future<Result<void>> submit({
    required StoreContext context,
    required String draftId,
  }) =>
      _action('submitVoucherDraft', context, draftId);

  @override
  Future<Result<void>> approve({
    required StoreContext context,
    required String draftId,
  }) =>
      _action('approveVoucherDraft', context, draftId);

  @override
  Future<Result<void>> reject({
    required StoreContext context,
    required String draftId,
    required String reason,
  }) =>
      _action(
        'rejectVoucherDraft',
        context,
        draftId,
        reason: reason,
      );

  Future<Result<void>> _action(
    String name,
    StoreContext context,
    String draftId, {
    String? reason,
    Map<String, dynamic>? extra,
  }) async {
    if (context.storeId.trim().isEmpty ||
        context.userId.trim().isEmpty ||
        draftId.trim().isEmpty ||
        draftId.contains('/')) {
      return const FailureResult<void>(
        ValidationFailure('Draft identifier or store is invalid.'),
      );
    }
    try {
      final result =
          await _functions.httpsCallable(name).call<Map<String, dynamic>>({
        'storeId': context.storeId,
        'draftId': draftId,
        if (reason != null) 'reason': reason,
        if (extra != null) ...extra,
      });
      if (result.data['draftId'] != draftId) {
        return const FailureResult<void>(
          InfrastructureFailure('Draft service returned the wrong identifier.'),
        );
      }
      return const Success<void>(null);
    } on cloud_functions.FirebaseFunctionsException catch (error) {
      return FailureResult<void>(_functionFailure(error));
    } catch (error) {
      return FailureResult<void>(InfrastructureFailure(error.toString()));
    }
  }

  @override
  Future<Result<List<VoucherDraft>>> getRecentDrafts({
    required StoreContext context,
  }) async {
    if (context.storeId.trim().isEmpty || context.userId.trim().isEmpty) {
      return const FailureResult<List<VoucherDraft>>(
        ValidationFailure('Store and user are required.'),
      );
    }
    try {
      final snapshot = await FirebasePaths.store(
        _firestore,
        context.storeId,
      )
          .collection('voucher_drafts')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get();
      final drafts = <VoucherDraft>[];
      for (final document in snapshot.docs) {
        final data = document.data();
        if (data['storeId'] != context.storeId) {
          throw const FormatException('Draft belongs to another store.');
        }
        final command = data['financialRequest'];
        if (command is! Map<String, dynamic> ||
            command['storeId'] != context.storeId) {
          throw const FormatException(
              'Draft does not have its posting command.');
        }
        final payment = command['payment'];
        if (payment is! Map<String, dynamic> ||
            payment['id'] != document.id ||
            payment['partyId'] is! String ||
            payment['currency'] is! String ||
            payment['amountMinorUnits'] is! int ||
            (payment['amountMinorUnits'] as int) <= 0 ||
            data['createdBy'] is! String ||
            data['status'] is! String) {
          throw const FormatException('Draft has invalid financial fields.');
        }
        final type = switch (payment['partyType']) {
          'customer' => PartyType.customer,
          'supplier' => PartyType.supplier,
          _ => throw const FormatException('Draft party type is invalid.'),
        };
        final postedAt = DateTime.tryParse(
          payment['postedAt']?.toString() ?? '',
        );
        if (postedAt == null) {
          throw const FormatException('Draft date is invalid.');
        }
        drafts.add(
          VoucherDraft(
            id: document.id,
            storeId: context.storeId,
            revision: data['revision'] is int ? data['revision'] as int : 1,
            createdBy: data['createdBy'] as String,
            status: data['status'] as String,
            partyId: payment['partyId'] as String,
            partyType: type,
            amount: Money(
              minorUnits: payment['amountMinorUnits'] as int,
              currency: payment['currency'] as String,
            ),
            description: payment['description'] as String?,
            postedAt: postedAt.toUtc(),
            approvedBy: data['approvedBy'] as String?,
            journalEntryId: data['journalEntryId'] as String?,
            rejectionReason: data['rejectionReason'] as String?,
          ),
        );
      }
      return Success<List<VoucherDraft>>(drafts);
    } on FirebaseException catch (error) {
      return FailureResult<List<VoucherDraft>>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } on FormatException catch (error) {
      return FailureResult<List<VoucherDraft>>(
        ValidationFailure(error.message),
      );
    } catch (error) {
      return FailureResult<List<VoucherDraft>>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  Failure _functionFailure(
    cloud_functions.FirebaseFunctionsException error,
  ) {
    if (error.code == 'permission-denied' || error.code == 'unauthenticated') {
      return AuthorizationFailure(error.message ?? 'Access denied.');
    }
    if (error.code == 'invalid-argument') {
      return ValidationFailure(error.message ?? 'Invalid voucher action.');
    }
    if (error.code == 'failed-precondition' ||
        error.code == 'already-exists' ||
        error.code == 'aborted') {
      return ConflictFailure(error.message ?? 'Voucher state has changed.');
    }
    return InfrastructureFailure(error.message ?? error.code);
  }
}
