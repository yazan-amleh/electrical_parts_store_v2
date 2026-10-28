import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' as firebase_functions;

import '../../../../core/commands/command_queue_repository.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../domain/entities/purchase.dart';
import '../../domain/entities/purchase_posting_plan.dart';
import '../../domain/entities/purchase_invoice.dart';
import '../../domain/entities/purchase_return.dart';
import '../../domain/repositories/purchase_repository.dart';
import '../../../../infrastructure/queue/cloud_function_queue_fallback.dart';
import '../../domain/services/purchase_posting_planner.dart';
import '../mappers/purchase_command_mapper.dart';
import '../mappers/purchase_return_command_mapper.dart';
import '../../../../infrastructure/firebase/firebase_paths.dart';

class FirestorePurchaseRepository implements PurchaseRepository {
  FirestorePurchaseRepository({
    required FirebaseFirestore firestore,
    required firebase_functions.FirebaseFunctions functions,
    CommandQueueRepository? commandQueue,
    PurchasePostingPlanner planner = const PurchasePostingPlanner(),
  })  : _firestore = firestore,
        _functions = functions,
        _planner = planner,
        _commandQueue = commandQueue;

  final FirebaseFirestore _firestore;
  final firebase_functions.FirebaseFunctions _functions;
  final PurchasePostingPlanner _planner;
  final CommandQueueRepository? _commandQueue;

  @override
  Future<Result<PurchasePostingPlan>> postPurchase({
    required StoreContext context,
    required Purchase purchase,
    required PurchasePostingAccounts accounts,
  }) async {
    final prepared = _planner.prepare(
      context: context,
      purchase: purchase,
      accounts: accounts,
    );
    if (prepared is FailureResult<PurchasePostingPlan>) {
      return FailureResult<PurchasePostingPlan>(prepared.failure);
    }

    final plan = (prepared as Success<PurchasePostingPlan>).value;

    try {
      final callable = _functions.httpsCallable('postPurchase');
      final response = await callable.call<Map<String, dynamic>>(
        PurchaseCommandMapper.toRequest(purchase: purchase, accounts: accounts),
      );
      final data = response.data;
      if (data['purchaseId'] != purchase.id) {
        return const FailureResult<PurchasePostingPlan>(
          InfrastructureFailure(
            'The purchase service returned another purchase id.',
          ),
        );
      }

      return Success<PurchasePostingPlan>(plan);
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      if (_commandQueue != null &&
          CloudFunctionQueueFallback.isTransient(error)) {
        final commandId = 'purchase-${purchase.id}';
        final queueFailure = await CloudFunctionQueueFallback.enqueue(
          repository: _commandQueue,
          context: context,
          commandId: commandId,
          operation: 'postPurchase',
          idempotencyKey: purchase.idempotencyKey.value,
          payload: PurchaseCommandMapper.toRequest(
            purchase: purchase,
            accounts: accounts,
          ),
        );
        if (queueFailure != null) {
          return FailureResult<PurchasePostingPlan>(queueFailure);
        }
        return FailureResult<PurchasePostingPlan>(
          QueuedFailure(commandId: commandId),
        );
      }
      return FailureResult<PurchasePostingPlan>(_mapFailure(error));
    } catch (error) {
      return FailureResult<PurchasePostingPlan>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<List<PurchaseInvoiceSummary>>> getRecentPurchaseInvoices({
    required StoreContext context,
    int limit = 100,
  }) async {
    if (limit <= 0 || limit > 500) {
      return const FailureResult<List<PurchaseInvoiceSummary>>(
        ValidationFailure('Purchase invoice limit must be between 1 and 500.'),
      );
    }

    try {
      final snapshot = await FirebasePaths.purchases(
        _firestore,
        context.storeId,
      ).orderBy('postedAt', descending: true).limit(limit).get();
      final invoices = <PurchaseInvoiceSummary>[];
      for (final document in snapshot.docs) {
        final invoice = _mapInvoiceSummary(
          document,
          expectedStoreId: context.storeId,
        );
        if (invoice != null) {
          invoices.add(invoice);
        }
      }
      return Success<List<PurchaseInvoiceSummary>>(
        List.unmodifiable(invoices),
      );
    } on FirebaseException catch (error) {
      return FailureResult<List<PurchaseInvoiceSummary>>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } on FormatException catch (error) {
      return FailureResult<List<PurchaseInvoiceSummary>>(
        ValidationFailure(error.message.toString()),
      );
    } catch (error) {
      return FailureResult<List<PurchaseInvoiceSummary>>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<PurchaseInvoiceDocument>> getPurchaseInvoiceDocument({
    required StoreContext context,
    required String purchaseId,
  }) async {
    if (purchaseId.trim().isEmpty || purchaseId.contains('/')) {
      return const FailureResult<PurchaseInvoiceDocument>(
        ValidationFailure('Purchase invoice id is invalid.'),
      );
    }

    try {
      final reference = FirebasePaths.purchases(
        _firestore,
        context.storeId,
      ).doc(purchaseId);
      final snapshot = await reference.get();
      if (!snapshot.exists) {
        return const FailureResult<PurchaseInvoiceDocument>(
          ValidationFailure('Purchase invoice was not found.'),
        );
      }
      final invoice = _mapInvoiceSummary(
        snapshot,
        expectedStoreId: context.storeId,
      );
      if (invoice == null) {
        return const FailureResult<PurchaseInvoiceDocument>(
          ValidationFailure('Purchase invoice is not posted.'),
        );
      }

      final data = snapshot.data() ?? const <String, dynamic>{};
      final returnedQuantityByLine = <String, int>{};
      final rawReturnedLines = data['returnedLines'];
      if (rawReturnedLines != null) {
        if (rawReturnedLines is! List) {
          throw const FormatException(
            'Purchase invoice return projection is malformed.',
          );
        }
        for (final rawProjection in rawReturnedLines) {
          if (rawProjection is! Map) {
            throw const FormatException(
              'Purchase invoice returned line projection is malformed.',
            );
          }
          final projection = Map<String, dynamic>.from(rawProjection);
          final lineId = _requiredId(projection['lineId'], 'return line id');
          final returnedQuantity = _requiredNonNegativeInt(
            projection['returnedQuantityMilliUnits'],
            'returned quantity',
          );
          if (returnedQuantity <= 0 ||
              returnedQuantityByLine.containsKey(lineId)) {
            throw const FormatException(
              'Purchase invoice return projection is inconsistent.',
            );
          }
          returnedQuantityByLine[lineId] = returnedQuantity;
        }
      }
      if (invoice.isPartiallyReturned && returnedQuantityByLine.isEmpty) {
        throw const FormatException(
          'Partially returned purchase has no line projection.',
        );
      }

      final linesSnapshot = await reference.collection('lines').get();
      if (linesSnapshot.docs.isEmpty || linesSnapshot.docs.length > 100) {
        throw const FormatException(
          'Purchase invoice has no verifiable line snapshot.',
        );
      }

      final lines = <PurchaseInvoiceLineSummary>[];
      var verifiedSubtotal = 0;
      for (final lineDocument in linesSnapshot.docs) {
        final line = lineDocument.data();
        final lineId = _requiredId(line['id'], 'purchase line id');
        if (lineId != lineDocument.id) {
          throw const FormatException(
            'Purchase invoice line identity is inconsistent.',
          );
        }
        final quantity = _requiredPositiveInt(
          line['quantityMilliUnits'],
          'purchase line quantity',
        );
        final baseQuantity = _requiredPositiveInt(
          line['baseQuantityMilliUnits'],
          'purchase line base quantity',
        );
        final unitCost = _requiredNonNegativeInt(
          line['unitCostMinorUnits'],
          'purchase line unit cost',
        );
        final discount = _requiredNonNegativeInt(
          line['discountMinorUnits'],
          'purchase line discount',
        );
        final gross = _requiredNonNegativeInt(
          line['grossTotalMinorUnits'],
          'purchase line gross',
        );
        final total = _requiredNonNegativeInt(
          line['totalMinorUnits'],
          'purchase line total',
        );
        if (discount > gross || gross - discount != total) {
          throw const FormatException(
            'Purchase invoice line totals do not reconcile.',
          );
        }
        final returnedQuantity = invoice.isFullyReturned &&
                returnedQuantityByLine.isEmpty
            ? quantity
            : (returnedQuantityByLine[lineId] ?? 0);
        if (returnedQuantity > quantity) {
          throw const FormatException(
            'Purchase invoice returned quantity exceeds source quantity.',
          );
        }
        verifiedSubtotal += total;
        lines.add(
          PurchaseInvoiceLineSummary(
            id: lineId,
            productId: _requiredId(
              line['productId'],
              'purchase line product id',
            ),
            description: _requiredString(
              line['description'],
              'purchase line description',
            ),
            quantityMilliUnits: quantity,
            baseQuantityMilliUnits: baseQuantity,
            unitCost: Money(
              minorUnits: unitCost,
              currency: invoice.total.currency,
            ),
            discount: Money(
              minorUnits: discount,
              currency: invoice.total.currency,
            ),
            total: Money(
              minorUnits: total,
              currency: invoice.total.currency,
            ),
            returnedQuantityMilliUnits: returnedQuantity,
            unitName: _nullableString(line['unitName']),
          ),
        );
      }
      if (verifiedSubtotal != invoice.subtotal.minorUnits) {
        throw const FormatException(
          'Purchase invoice lines do not match invoice subtotal.',
        );
      }

      return Success<PurchaseInvoiceDocument>(
        PurchaseInvoiceDocument(
          invoice: invoice,
          lines: List.unmodifiable(lines),
        ),
      );
    } on FirebaseException catch (error) {
      return FailureResult<PurchaseInvoiceDocument>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } on FormatException catch (error) {
      return FailureResult<PurchaseInvoiceDocument>(
        ValidationFailure(error.message.toString()),
      );
    } catch (error) {
      return FailureResult<PurchaseInvoiceDocument>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<PurchaseReturnPostingResult>> postPurchaseReturn({
    required StoreContext context,
    required PurchaseReturn purchaseReturn,
    required PurchaseReturnPostingAccounts accounts,
  }) async {
    if (purchaseReturn.storeId != context.storeId) {
      return const FailureResult<PurchaseReturnPostingResult>(
        ValidationFailure('Purchase return belongs to another store.'),
      );
    }

    try {
      final callable = _functions.httpsCallable('postPurchaseReturn');
      final response = await callable.call<Map<String, dynamic>>(
        PurchaseReturnCommandMapper.toRequest(
          purchaseReturn: purchaseReturn,
          accounts: accounts,
        ),
      );
      final data = response.data;
      final status = data['status'];
      final returnStatus = data['returnStatus'];
      final carryingValue = data['inventoryCarryingValueMinorUnits'];
      final variance = data['valuationVarianceMinorUnits'];
      if (data['returnId'] != purchaseReturn.id ||
          data['originalPurchaseId'] != purchaseReturn.originalPurchaseId ||
          data['journalEntryId'] is! String ||
          (status != 'returned' && status != 'already_returned') ||
          (returnStatus != 'partial' && returnStatus != 'full') ||
          carryingValue is! int ||
          variance is! int) {
        return const FailureResult<PurchaseReturnPostingResult>(
          InfrastructureFailure(
            'The purchase return service returned inconsistent data.',
          ),
        );
      }

      return Success<PurchaseReturnPostingResult>(
        PurchaseReturnPostingResult(
          returnId: purchaseReturn.id,
          originalPurchaseId: purchaseReturn.originalPurchaseId,
          journalEntryId: data['journalEntryId'] as String,
          alreadyReturned: status == 'already_returned',
          returnStatus: returnStatus as String,
          inventoryCarryingValueMinorUnits: carryingValue,
          valuationVarianceMinorUnits: variance,
        ),
      );
    } on firebase_functions.FirebaseFunctionsException catch (error) {
      return FailureResult<PurchaseReturnPostingResult>(_mapFailure(error));
    } catch (error) {
      return FailureResult<PurchaseReturnPostingResult>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  PurchaseInvoiceSummary? _mapInvoiceSummary(
    DocumentSnapshot<Map<String, dynamic>> snapshot, {
    required String expectedStoreId,
  }) {
    final data = snapshot.data();
    if (data == null || data['status'] != 'posted') {
      return null;
    }
    if (data['storeId'] != expectedStoreId) {
      throw const FormatException('Purchase invoice belongs to another store.');
    }

    final postedAt = _date(data['postedAt']);
    if (postedAt == null) {
      throw const FormatException('Purchase invoice posting date is invalid.');
    }
    final currency = _requiredString(data['currency'], 'purchase currency');
    final subtotal = _requiredNonNegativeInt(
      data['subtotalMinorUnits'],
      'purchase subtotal',
    );
    final tax = _requiredNonNegativeInt(
      data['taxMinorUnits'],
      'purchase tax',
    );
    final total = _requiredNonNegativeInt(
      data['totalMinorUnits'],
      'purchase total',
    );
    if (subtotal <= 0 || subtotal + tax != total) {
      throw const FormatException('Purchase invoice totals do not reconcile.');
    }
    final paymentMethod = _requiredString(
      data['paymentMethod'],
      'purchase payment method',
    );
    if (!const {'cash', 'bank', 'card', 'credit'}.contains(paymentMethod)) {
      throw const FormatException('Purchase payment method is unsupported.');
    }
    final returnStatus = _nullableString(data['returnStatus']);
    if (returnStatus != null &&
        returnStatus != 'partial' &&
        returnStatus != 'full') {
      throw const FormatException('Purchase return status is invalid.');
    }

    return PurchaseInvoiceSummary(
      id: snapshot.id,
      storeId: expectedStoreId,
      postedAt: postedAt,
      paymentMethod: paymentMethod,
      supplierId: _nullableString(data['supplierId']),
      description: _nullableString(data['description']),
      subtotal: Money(minorUnits: subtotal, currency: currency),
      tax: Money(minorUnits: tax, currency: currency),
      total: Money(minorUnits: total, currency: currency),
      journalEntryId: _requiredId(
        data['journalEntryId'],
        'purchase journal id',
      ),
      returnStatus: returnStatus,
      returnId: _nullableString(data['returnId']),
      returnedAt: _date(data['returnedAt']),
    );
  }

  static String _requiredString(Object? value, String label) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$label is invalid.');
    }
    return value.trim();
  }

  static String _requiredId(Object? value, String label) {
    final result = _requiredString(value, label);
    if (result.contains('/')) {
      throw FormatException('$label is invalid.');
    }
    return result;
  }

  static String? _nullableString(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw const FormatException('Expected an optional string.');
    }
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static int _requiredNonNegativeInt(Object? value, String label) {
    if (value is! int || value < 0) {
      throw FormatException('$label is invalid.');
    }
    return value;
  }

  static int _requiredPositiveInt(Object? value, String label) {
    final result = _requiredNonNegativeInt(value, label);
    if (result <= 0) {
      throw FormatException('$label must be positive.');
    }
    return result;
  }

  static DateTime? _date(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is Timestamp) {
      return value.toDate().toUtc();
    }
    if (value is DateTime) {
      return value.toUtc();
    }
    throw const FormatException('Expected a Firestore timestamp.');
  }

  Failure _mapFailure(firebase_functions.FirebaseFunctionsException error) {
    switch (error.code) {
      case 'permission-denied':
      case 'unauthenticated':
        return AuthorizationFailure(
          error.message ?? 'Purchase is not authorized.',
        );
      case 'invalid-argument':
      case 'failed-precondition':
        return ValidationFailure(error.message ?? 'Purchase is invalid.');
      case 'already-exists':
      case 'aborted':
        return ConflictFailure(
          error.message ?? 'Purchase conflicts with existing data.',
        );
      default:
        return InfrastructureFailure(error.message ?? error.code);
    }
  }
}
