import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/money/money.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../../infrastructure/firebase/firebase_paths.dart';
import '../../domain/entities/operational_report.dart';
import '../../domain/repositories/reports_repository.dart';
import '../mappers/report_firestore_mapper.dart';

class FirestoreReportsRepository implements ReportsRepository {
  FirestoreReportsRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  @override
  Future<Result<OperationalReport>> getOperationalReport({
    required StoreContext context,
    required DateTime from,
    required DateTime to,
    int limit = 500,
  }) async {
    if (from.isAfter(to)) {
      return const FailureResult<OperationalReport>(
        ValidationFailure('Report start date cannot be after end date.'),
      );
    }
    if (limit <= 0 || limit > 2000) {
      return const FailureResult<OperationalReport>(
        ValidationFailure('Report limit must be between 1 and 2000.'),
      );
    }

    final start = Timestamp.fromDate(from.toUtc());
    final end = Timestamp.fromDate(to.toUtc());

    try {
      final snapshots = await Future.wait<QuerySnapshot<Map<String, dynamic>>>([
        FirebasePaths.sales(_firestore, context.storeId)
            .where('postedAt', isGreaterThanOrEqualTo: start)
            .where('postedAt', isLessThanOrEqualTo: end)
            .limit(limit)
            .get(),
        FirebasePaths.purchases(_firestore, context.storeId)
            .where('postedAt', isGreaterThanOrEqualTo: start)
            .where('postedAt', isLessThanOrEqualTo: end)
            .limit(limit)
            .get(),
        FirebasePaths.expenses(_firestore, context.storeId)
            .where('postedAt', isGreaterThanOrEqualTo: start)
            .where('postedAt', isLessThanOrEqualTo: end)
            .limit(limit)
            .get(),
      ]);

      final transactions = <ReportTransaction>[];
      for (final document in snapshots[0].docs) {
        final transaction = ReportFirestoreMapper.tryTransaction(
          document,
          source: 'sale',
        );
        if (transaction != null) {
          transactions.add(transaction);
        }
      }
      for (final document in snapshots[1].docs) {
        final transaction = ReportFirestoreMapper.tryTransaction(
          document,
          source: 'purchase',
        );
        if (transaction != null) {
          transactions.add(transaction);
        }
      }
      for (final document in snapshots[2].docs) {
        final transaction = ReportFirestoreMapper.tryTransaction(
          document,
          source: 'expense',
        );
        if (transaction != null) {
          transactions.add(transaction);
        }
      }

      String? currency;
      for (final transaction in transactions) {
        currency ??= transaction.amount.currency;
        if (transaction.amount.currency != currency ||
            transaction.cost.currency != currency) {
          return const FailureResult<OperationalReport>(
            ValidationFailure(
              'A report cannot combine transactions in different currencies.',
            ),
          );
        }
      }
      final reportCurrency = currency ?? 'ILS';
      var salesRevenue = Money.zero(currency: reportCurrency);
      var salesCost = Money.zero(currency: reportCurrency);
      var purchasesTotal = Money.zero(currency: reportCurrency);
      var expensesTotal = Money.zero(currency: reportCurrency);
      final salesByPaymentMethod = <String, int>{};
      final expensesByPaymentMethod = <String, int>{};
      var salesCount = 0;
      var purchasesCount = 0;
      var expensesCount = 0;

      for (final transaction in transactions) {
        switch (transaction.source) {
          case 'sale':
            salesRevenue += transaction.amount;
            salesCost += transaction.cost;
            salesCount++;
            _increment(
              salesByPaymentMethod,
              transaction.paymentMethod ?? 'unknown',
            );
          case 'purchase':
            purchasesTotal += transaction.amount;
            purchasesCount++;
          case 'expense':
            expensesTotal += transaction.amount;
            expensesCount++;
            _increment(
              expensesByPaymentMethod,
              transaction.paymentMethod ?? 'unknown',
            );
        }
      }

      transactions.sort(
        (left, right) => right.postedAt.compareTo(left.postedAt),
      );

      return Success<OperationalReport>(
        OperationalReport(
          from: from.toUtc(),
          to: to.toUtc(),
          salesRevenue: salesRevenue,
          salesCost: salesCost,
          purchasesTotal: purchasesTotal,
          expensesTotal: expensesTotal,
          salesCount: salesCount,
          purchasesCount: purchasesCount,
          expensesCount: expensesCount,
          salesByPaymentMethod: Map.unmodifiable(salesByPaymentMethod),
          expensesByPaymentMethod: Map.unmodifiable(expensesByPaymentMethod),
          transactions: List.unmodifiable(transactions),
        ),
      );
    } on FirebaseException catch (error) {
      return FailureResult<OperationalReport>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<OperationalReport>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  static void _increment(Map<String, int> values, String key) {
    values[key] = (values[key] ?? 0) + 1;
  }
}
