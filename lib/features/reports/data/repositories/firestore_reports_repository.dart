import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/money/money.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../../infrastructure/firebase/firebase_paths.dart';
import '../../domain/entities/operational_report.dart';
import '../../domain/entities/sales_analytics.dart';
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
    int maxDocuments = 10000,
  }) async {
    if (from.isAfter(to)) {
      return const FailureResult<OperationalReport>(
        ValidationFailure('Report start date cannot be after end date.'),
      );
    }
    if (limit <= 0 ||
        limit > 2000 ||
        maxDocuments <= 0 ||
        maxDocuments > 100000) {
      return const FailureResult<OperationalReport>(
        ValidationFailure(
          'Report page size must be between 1 and 2000 and max documents '
          'must be between 1 and 100000.',
        ),
      );
    }

    final start = Timestamp.fromDate(from.toUtc());
    final end = Timestamp.fromDate(to.toUtc());

    try {
      final pages = await Future.wait<_PagedDocuments>([
        _readPeriodDocuments(
          collection: FirebasePaths.sales(_firestore, context.storeId),
          start: start,
          end: end,
          pageSize: limit,
          maxDocuments: maxDocuments,
        ),
        _readPeriodDocuments(
          collection: FirebasePaths.purchases(_firestore, context.storeId),
          start: start,
          end: end,
          pageSize: limit,
          maxDocuments: maxDocuments,
        ),
        _readPeriodDocuments(
          collection: FirebasePaths.expenses(_firestore, context.storeId),
          start: start,
          end: end,
          pageSize: limit,
          maxDocuments: maxDocuments,
        ),
      ]);

      final transactions = <ReportTransaction>[];
      for (final document in pages[0].documents) {
        final transaction = ReportFirestoreMapper.tryTransaction(
          document,
          source: 'sale',
        );
        if (transaction != null) {
          transactions.add(transaction);
        }
      }
      for (final document in pages[1].documents) {
        final transaction = ReportFirestoreMapper.tryTransaction(
          document,
          source: 'purchase',
        );
        if (transaction != null) {
          transactions.add(transaction);
        }
      }
      for (final document in pages[2].documents) {
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
          mayBeTruncated: pages.any((page) => page.mayBeTruncated),
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

  @override
  Future<Result<SalesAnalytics>> getSalesAnalytics({
    required StoreContext context,
    required DateTime from,
    required DateTime to,
    int limit = 500,
    int maxDocuments = 10000,
  }) async {
    if (from.isAfter(to)) {
      return const FailureResult<SalesAnalytics>(
        ValidationFailure('Report start date cannot be after end date.'),
      );
    }
    if (limit <= 0 ||
        limit > 2000 ||
        maxDocuments <= 0 ||
        maxDocuments > 100000) {
      return const FailureResult<SalesAnalytics>(
        ValidationFailure(
          'Report page size must be between 1 and 2000 and max documents '
          'must be between 1 and 100000.',
        ),
      );
    }

    final start = Timestamp.fromDate(from.toUtc());
    final end = Timestamp.fromDate(to.toUtc());

    try {
      final salesPageFuture = _readPeriodDocuments(
        collection: FirebasePaths.sales(_firestore, context.storeId),
        start: start,
        end: end,
        pageSize: limit,
        maxDocuments: maxDocuments,
      );
      final lookupSnapshots =
          await Future.wait<QuerySnapshot<Map<String, dynamic>>>([
        FirebasePaths.products(_firestore, context.storeId).get(),
        FirebasePaths.categories(_firestore, context.storeId).get(),
        FirebasePaths.parties(_firestore, context.storeId).get(),
      ]);
      final salesPage = await salesPageFuture;

      final productLookup = <String, _ProductAnalyticsLookup>{};
      for (final document in lookupSnapshots[0].docs) {
        final data = document.data();
        final productId = document.id;
        final name = _analyticsString(data['name'], productId);
        final categoryId = _analyticsString(
          data['categoryId'],
          'uncategorized',
        );
        productLookup[productId] = _ProductAnalyticsLookup(
          name: name,
          categoryId: categoryId,
        );
      }

      final categoryNames = <String, String>{};
      for (final document in lookupSnapshots[1].docs) {
        final data = document.data();
        categoryNames[document.id] = _analyticsString(
          data['name'],
          document.id,
        );
      }

      final partyNames = <String, String>{};
      for (final document in lookupSnapshots[2].docs) {
        final data = document.data();
        partyNames[document.id] = _analyticsString(data['name'], document.id);
      }

      String? currency;
      var salesRevenue = Money.zero(currency: 'ILS');
      var salesCost = Money.zero(currency: 'ILS');
      var salesCount = 0;
      final paymentMethodCounts = <String, int>{};
      final productRows = <String, _AnalyticsAccumulator>{};
      final categoryRows = <String, _AnalyticsAccumulator>{};
      final customerRows = <String, _AnalyticsAccumulator>{};

      for (final document in salesPage.documents) {
        final data = document.data();
        final postedAt = _analyticsDate(data['postedAt']);
        if (postedAt == null) {
          continue;
        }

        final saleCurrency = _analyticsString(data['currency'], 'ILS');
        if (currency == null) {
          currency = saleCurrency;
          salesRevenue = Money.zero(currency: saleCurrency);
          salesCost = Money.zero(currency: saleCurrency);
        } else if (saleCurrency != currency) {
          return const FailureResult<SalesAnalytics>(
            ValidationFailure(
              'Sales analytics cannot combine different currencies.',
            ),
          );
        }

        final saleTotalMinorUnits = _analyticsInt(
          data['totalMinorUnits'],
          _analyticsInt(data['amountMinorUnits']),
        );
        final saleCostMinorUnits = _analyticsInt(data['costTotalMinorUnits']);
        salesRevenue += Money(
          minorUnits: saleTotalMinorUnits,
          currency: saleCurrency,
        );
        salesCost += Money(
          minorUnits: saleCostMinorUnits,
          currency: saleCurrency,
        );
        salesCount++;
        _increment(
          paymentMethodCounts,
          _analyticsString(data['paymentMethod'], 'unknown'),
        );

        final customerId = _analyticsNullableString(data['customerId']);
        final customerKey = customerId ?? 'walk-in';
        final customerLabel = customerId == null
            ? 'مبيعات نقدية / بدون عميل'
            : (partyNames[customerId] ?? customerId);
        _addAnalyticsRow(
          customerRows,
          key: customerKey,
          label: customerLabel,
          quantityMilliUnits: 0,
          revenueMinorUnits: saleTotalMinorUnits,
          costMinorUnits: saleCostMinorUnits,
          currency: saleCurrency,
        );

        final rawLines = data['lines'];
        if (rawLines is! List) {
          continue;
        }
        for (final rawLine in rawLines) {
          if (rawLine is! Map) {
            continue;
          }
          final line = Map<String, dynamic>.from(rawLine);
          final productId = _analyticsNullableString(line['productId']);
          final product = productId == null ? null : productLookup[productId];
          final fallbackLabel = _analyticsString(
            line['description'],
            productId ?? 'صنف غير معروف',
          );
          final productLabel = product?.name ?? fallbackLabel;
          final categoryId = product?.categoryId ?? 'uncategorized';
          final categoryLabel = categoryNames[categoryId] ?? 'غير مصنف';
          final quantityMilliUnits = _analyticsInt(line['quantityMilliUnits']);
          final factorMilliUnits = _analyticsInt(
            line['unitFactorToBaseMilliUnits'],
            1000,
          );
          final baseQuantityMilliUnits = _scaled(
            quantityMilliUnits,
            factorMilliUnits,
          );
          final lineRevenueMinorUnits = _nonNegative(
            _scaled(
                  _analyticsInt(line['unitPriceMinorUnits']),
                  quantityMilliUnits,
                ) -
                _analyticsInt(line['discountMinorUnits']),
          );
          final isService =
              line['isService'] is bool && line['isService'] as bool;
          final lineCostMinorUnits = isService
              ? 0
              : _scaled(
                  _analyticsInt(line['unitCostMinorUnits']),
                  baseQuantityMilliUnits,
                );

          _addAnalyticsRow(
            productRows,
            key: productId ?? fallbackLabel,
            label: productLabel,
            quantityMilliUnits: baseQuantityMilliUnits,
            revenueMinorUnits: lineRevenueMinorUnits,
            costMinorUnits: lineCostMinorUnits,
            currency: saleCurrency,
          );
          _addAnalyticsRow(
            categoryRows,
            key: categoryId,
            label: categoryLabel,
            quantityMilliUnits: baseQuantityMilliUnits,
            revenueMinorUnits: lineRevenueMinorUnits,
            costMinorUnits: lineCostMinorUnits,
            currency: saleCurrency,
          );
        }
      }

      final analyticsCurrency = currency ?? 'ILS';
      final sortRows = <_AnalyticsAccumulator>[...productRows.values]
        ..sort(_compareAnalyticsRows);
      final sortedCategories = <_AnalyticsAccumulator>[...categoryRows.values]
        ..sort(_compareAnalyticsRows);
      final sortedCustomers = <_AnalyticsAccumulator>[...customerRows.values]
        ..sort(_compareAnalyticsRows);

      return Success<SalesAnalytics>(
        SalesAnalytics(
          from: from.toUtc(),
          to: to.toUtc(),
          salesRevenue: currency == null
              ? Money.zero(currency: analyticsCurrency)
              : salesRevenue,
          salesCost: currency == null
              ? Money.zero(currency: analyticsCurrency)
              : salesCost,
          salesCount: salesCount,
          paymentMethodCounts: Map.unmodifiable(paymentMethodCounts),
          productRows: List.unmodifiable(sortRows.map((row) => row.toEntity())),
          categoryRows: List.unmodifiable(
            sortedCategories.map((row) => row.toEntity()),
          ),
          customerRows: List.unmodifiable(
            sortedCustomers.map((row) => row.toEntity()),
          ),
          mayBeTruncated: salesPage.documents.length >= limit,
        ),
      );
    } on FirebaseException catch (error) {
      return FailureResult<SalesAnalytics>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<SalesAnalytics>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  Future<_PagedDocuments> _readPeriodDocuments({
    required CollectionReference<Map<String, dynamic>> collection,
    required Timestamp start,
    required Timestamp end,
    required int pageSize,
    required int maxDocuments,
  }) async {
    final documents = <DocumentSnapshot<Map<String, dynamic>>>[];
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    var mayBeTruncated = false;

    while (documents.length < maxDocuments) {
      final remaining = maxDocuments - documents.length;
      final currentPageSize =
          remaining < pageSize ? remaining : pageSize;
      Query<Map<String, dynamic>> query = collection
          .where('postedAt', isGreaterThanOrEqualTo: start)
          .where('postedAt', isLessThanOrEqualTo: end)
          .orderBy('postedAt')
          .limit(currentPageSize);
      if (cursor != null) {
        query = query.startAfterDocument(cursor!);
      }

      final snapshot = await query.get();
      documents.addAll(snapshot.docs);
      if (snapshot.docs.length < currentPageSize) {
        break;
      }

      cursor = snapshot.docs.last;
      if (documents.length >= maxDocuments) {
        final probe = await collection
            .where('postedAt', isGreaterThanOrEqualTo: start)
            .where('postedAt', isLessThanOrEqualTo: end)
            .orderBy('postedAt')
            .startAfterDocument(cursor!)
            .limit(1)
            .get();
        mayBeTruncated = probe.docs.isNotEmpty;
        break;
      }
    }

    return _PagedDocuments(
      documents: List.unmodifiable(documents),
      mayBeTruncated: mayBeTruncated,
    );
  }

  static void _addAnalyticsRow(
    Map<String, _AnalyticsAccumulator> rows, {
    required String key,
    required String label,
    required int quantityMilliUnits,
    required int revenueMinorUnits,
    required int costMinorUnits,
    required String currency,
  }) {
    final current = rows[key];
    if (current == null) {
      rows[key] = _AnalyticsAccumulator(
        key: key,
        label: label,
        currency: currency,
        quantityMilliUnits: quantityMilliUnits,
        revenueMinorUnits: revenueMinorUnits,
        costMinorUnits: costMinorUnits,
      );
      return;
    }
    current.quantityMilliUnits += quantityMilliUnits;
    current.revenueMinorUnits += revenueMinorUnits;
    current.costMinorUnits += costMinorUnits;
  }

  static int _compareAnalyticsRows(
    _AnalyticsAccumulator left,
    _AnalyticsAccumulator right,
  ) {
    final revenue = right.revenueMinorUnits.compareTo(left.revenueMinorUnits);
    return revenue == 0
        ? left.label.toLowerCase().compareTo(right.label.toLowerCase())
        : revenue;
  }

  static int _scaled(int amount, int milliUnits) {
    final numerator = amount * milliUnits;
    return (numerator + 500) ~/ 1000;
  }

  static int _nonNegative(int value) => value < 0 ? 0 : value;

  static DateTime? _analyticsDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate().toUtc();
    }
    if (value is DateTime) {
      return value.toUtc();
    }
    return null;
  }

  static String _analyticsString(Object? value, String fallback) {
    return value is String && value.trim().isNotEmpty ? value.trim() : fallback;
  }

  static String? _analyticsNullableString(Object? value) {
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  static int _analyticsInt(Object? value, [int fallback = 0]) {
    return value is int
        ? value
        : value is num
            ? value.toInt()
            : fallback;
  }

  static void _increment(Map<String, int> values, String key) {
    values[key] = (values[key] ?? 0) + 1;
  }
}

class _ProductAnalyticsLookup {
  const _ProductAnalyticsLookup({required this.name, required this.categoryId});

  final String name;
  final String categoryId;
}

class _AnalyticsAccumulator {
  _AnalyticsAccumulator({
    required this.key,
    required this.label,
    required this.currency,
    required this.quantityMilliUnits,
    required this.revenueMinorUnits,
    required this.costMinorUnits,
  });

  final String key;
  final String label;
  final String currency;
  int quantityMilliUnits;
  int revenueMinorUnits;
  int costMinorUnits;

  SalesAnalyticsRow toEntity() {
    return SalesAnalyticsRow(
      key: key,
      label: label,
      quantityMilliUnits: quantityMilliUnits,
      revenue: Money(minorUnits: revenueMinorUnits, currency: currency),
      cost: Money(minorUnits: costMinorUnits, currency: currency),
    );
  }
}
