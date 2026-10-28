import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/money/money.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../../infrastructure/firebase/firebase_paths.dart';
import '../../domain/entities/operational_report.dart';
import '../../domain/entities/sales_analytics.dart';
import '../../domain/entities/sales_invoice_report.dart';
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
        _readPeriodDocuments(
          collection: FirebasePaths.salesReturns(_firestore, context.storeId),
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
      for (final document in pages[3].documents) {
        final transaction = ReportFirestoreMapper.tryTransaction(
          document,
          source: 'saleReturn',
          sign: -1,
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
      var salesReturnCount = 0;
      var purchasesCount = 0;
      var expensesCount = 0;

      for (final transaction in transactions) {
        switch (transaction.source) {
          case 'sale':
            salesRevenue += transaction.amountBeforeTax;
            salesCost += transaction.cost;
            salesCount++;
            _increment(
              salesByPaymentMethod,
              transaction.paymentMethod ?? 'unknown',
            );
          case 'saleReturn':
            salesRevenue += transaction.amountBeforeTax;
            salesCost += transaction.cost;
            salesReturnCount++;
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
          salesReturnCount: salesReturnCount,
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
  Future<Result<SalesInvoiceReport>> getSalesInvoices({
    required StoreContext context,
    required DateTime from,
    required DateTime to,
    int limit = 250,
    int maxDocuments = 1000,
  }) async {
    if (context.storeId.trim().isEmpty ||
        from.isAfter(to) ||
        limit < 1 ||
        limit > 2000 ||
        maxDocuments < 1 ||
        maxDocuments > 10000) {
      return const FailureResult<SalesInvoiceReport>(
        ValidationFailure('Invalid sales invoice report scope or page limit.'),
      );
    }
    try {
      final page = await _readPeriodDocuments(
        collection: FirebasePaths.sales(_firestore, context.storeId),
        start: Timestamp.fromDate(from.toUtc()),
        end: Timestamp.fromDate(to.toUtc()),
        pageSize: limit,
        maxDocuments: maxDocuments,
      );
      final invoices = <SalesInvoiceSummary>[];
      for (final document in page.documents) {
        final data = document.data();
        if (data == null ||
            data['storeId'] != context.storeId ||
            data['status'] != 'posted') {
          return FailureResult<SalesInvoiceReport>(
            ValidationFailure(
              'Sale ${document.id} has invalid tenant or posting status.',
            ),
          );
        }
        final postedAt = _analyticsDate(data['postedAt']);
        final currency = data['currency'];
        final subtotal = data['subtotalMinorUnits'];
        final tax = data['taxMinorUnits'];
        final total = data['totalMinorUnits'];
        final cost = data['costTotalMinorUnits'];
        final journalId = data['journalEntryId'];
        if (postedAt == null ||
            currency is! String ||
            currency.isEmpty ||
            subtotal is! int ||
            subtotal < 0 ||
            tax is! int ||
            tax < 0 ||
            total is! int ||
            total <= 0 ||
            cost is! int ||
            cost < 0 ||
            subtotal + tax != total ||
            journalId is! String ||
            journalId.isEmpty) {
          return FailureResult<SalesInvoiceReport>(
            ValidationFailure(
              'Sale ${document.id} has incomplete or inconsistent totals.',
            ),
          );
        }
        invoices.add(SalesInvoiceSummary(
          id: document.id,
          storeId: context.storeId,
          postedAt: postedAt,
          customerId: _analyticsNullableString(data['customerId']),
          paymentMethod: _analyticsString(data['paymentMethod'], 'unknown'),
          subtotal: Money(minorUnits: subtotal, currency: currency),
          tax: Money(minorUnits: tax, currency: currency),
          total: Money(minorUnits: total, currency: currency),
          cost: Money(minorUnits: cost, currency: currency),
          journalEntryId: journalId,
          description: _analyticsNullableString(data['description']),
          returnStatus: _analyticsNullableString(data['returnStatus']),
          returnId: _analyticsNullableString(data['returnId']),
          returnedAt: _analyticsDate(data['returnedAt']),
        ));
      }
      invoices.sort((a, b) {
        final order = b.postedAt.compareTo(a.postedAt);
        return order == 0 ? a.id.compareTo(b.id) : order;
      });
      return Success<SalesInvoiceReport>(
        SalesInvoiceReport(
          invoices: List.unmodifiable(invoices),
          mayBeTruncated: page.mayBeTruncated,
        ),
      );
    } on FirebaseException catch (error) {
      return FailureResult<SalesInvoiceReport>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<SalesInvoiceReport>(
        InfrastructureFailure(error.toString()),
      );
    }
  }

  @override
  Future<Result<List<SalesInvoiceDocument>>> getSalesInvoiceDocuments({
    required StoreContext context,
    required List<String> invoiceIds,
    int maxInvoices = 100,
  }) async {
    if (context.storeId.trim().isEmpty ||
        maxInvoices < 1 ||
        maxInvoices > 100 ||
        invoiceIds.isEmpty) {
      return const FailureResult<List<SalesInvoiceDocument>>(
        ValidationFailure('Invalid sales invoice detail request.'),
      );
    }

    final ids = <String>[];
    final seen = <String>{};
    for (final rawId in invoiceIds) {
      final id = rawId.trim();
      if (id.isEmpty || id.contains('/')) {
        return const FailureResult<List<SalesInvoiceDocument>>(
          ValidationFailure('Invoice ids must be safe document ids.'),
        );
      }
      if (seen.add(id)) {
        ids.add(id);
      }
    }
    if (ids.length > maxInvoices) {
      return FailureResult<List<SalesInvoiceDocument>>(
        ValidationFailure(
          'At most $maxInvoices invoices can be loaded for one export.',
        ),
      );
    }

    try {
      final sales = FirebasePaths.sales(_firestore, context.storeId);
      final documents = <SalesInvoiceDocument>[];

      for (final invoiceId in ids) {
        final invoiceRef = sales.doc(invoiceId);
        final snapshot = await invoiceRef.get();
        final data = snapshot.data();
        if (!snapshot.exists ||
            data == null ||
            data['storeId'] != context.storeId ||
            data['status'] != 'posted') {
          return FailureResult<List<SalesInvoiceDocument>>(
            ValidationFailure(
              'Sale $invoiceId is missing, unposted, or belongs to another store.',
            ),
          );
        }

        final postedAt = _analyticsDate(data['postedAt']);
        final currency = data['currency'];
        final subtotal = data['subtotalMinorUnits'];
        final tax = data['taxMinorUnits'];
        final total = data['totalMinorUnits'];
        final cost = data['costTotalMinorUnits'];
        final journalId = data['journalEntryId'];
        if (postedAt == null ||
            currency is! String ||
            currency.isEmpty ||
            subtotal is! int ||
            subtotal < 0 ||
            tax is! int ||
            tax < 0 ||
            total is! int ||
            total <= 0 ||
            cost is! int ||
            cost < 0 ||
            subtotal + tax != total ||
            journalId is! String ||
            journalId.isEmpty) {
          return FailureResult<List<SalesInvoiceDocument>>(
            ValidationFailure(
              'Sale $invoiceId has incomplete or inconsistent totals.',
            ),
          );
        }

        final invoice = SalesInvoiceSummary(
          id: invoiceId,
          storeId: context.storeId,
          postedAt: postedAt,
          customerId: _analyticsNullableString(data['customerId']),
          paymentMethod: _analyticsString(data['paymentMethod'], 'unknown'),
          subtotal: Money(minorUnits: subtotal, currency: currency),
          tax: Money(minorUnits: tax, currency: currency),
          total: Money(minorUnits: total, currency: currency),
          cost: Money(minorUnits: cost, currency: currency),
          journalEntryId: journalId,
          description: _analyticsNullableString(data['description']),
          returnStatus: _analyticsNullableString(data['returnStatus']),
          returnId: _analyticsNullableString(data['returnId']),
          returnedAt: _analyticsDate(data['returnedAt']),
        );

        final returnedQuantityByLine = <String, int>{};
        final returnStatus = _analyticsNullableString(data['returnStatus']);
        final rawReturnedLines = data['returnedLines'];
        if (rawReturnedLines != null) {
          if (rawReturnedLines is! List) {
            return FailureResult<List<SalesInvoiceDocument>>(
              ValidationFailure(
                'Sale $invoiceId has malformed return projection.',
              ),
            );
          }
          for (final rawProjection in rawReturnedLines) {
            if (rawProjection is! Map) {
              return FailureResult<List<SalesInvoiceDocument>>(
                ValidationFailure(
                  'Sale $invoiceId has malformed returned line data.',
                ),
              );
            }
            final projection = Map<String, dynamic>.from(rawProjection);
            final lineId = _analyticsString(projection['lineId'], '');
            final returnedQuantity = _analyticsInt(
              projection['returnedQuantityMilliUnits'],
              -1,
            );
            if (lineId.isEmpty ||
                lineId.contains('/') ||
                returnedQuantity <= 0 ||
                returnedQuantityByLine.containsKey(lineId)) {
              return FailureResult<List<SalesInvoiceDocument>>(
                ValidationFailure(
                  'Sale $invoiceId has invalid returned line projection.',
                ),
              );
            }
            returnedQuantityByLine[lineId] = returnedQuantity;
          }
        }
        if (returnStatus == 'partial' && returnedQuantityByLine.isEmpty) {
          return FailureResult<List<SalesInvoiceDocument>>(
            ValidationFailure(
              'Sale $invoiceId is partially returned without line projection.',
            ),
          );
        }

        final embeddedLines = data['lines'];
        final rawLines = <Map<String, dynamic>>[];
        if (embeddedLines is List && embeddedLines.isNotEmpty) {
          for (final value in embeddedLines) {
            if (value is! Map) {
              return FailureResult<List<SalesInvoiceDocument>>(
                ValidationFailure(
                  'Sale $invoiceId has malformed embedded invoice lines.',
                ),
              );
            }
            rawLines.add(Map<String, dynamic>.from(value));
          }
        } else {
          final lineSnapshot = await invoiceRef.collection('lines').get();
          for (final lineDocument in lineSnapshot.docs) {
            final line = lineDocument.data();
            rawLines.add({
              ...line,
              'id': _analyticsString(line['id'], lineDocument.id),
            });
          }
        }

        if (rawLines.isEmpty) {
          return FailureResult<List<SalesInvoiceDocument>>(
            ValidationFailure(
              'Sale $invoiceId has no verifiable invoice lines.',
            ),
          );
        }

        final lineIds = <String>{};
        final lines = <SalesInvoiceLineSummary>[];
        var verifiedSubtotal = 0;
        var verifiedCost = 0;
        for (final line in rawLines) {
          final lineStoreId = line['storeId'];
          final id = _analyticsString(line['id'], '');
          final productId = _analyticsString(line['productId'], '');
          final description = _analyticsString(line['description'], '');
          final quantity = _analyticsInt(line['quantityMilliUnits'], -1);
          final unitPrice = _analyticsInt(line['unitPriceMinorUnits'], -1);
          final discount = _analyticsInt(line['discountMinorUnits'], -1);
          final gross = _analyticsInt(
            line['grossTotalMinorUnits'],
            quantity > 0 && unitPrice >= 0 ? _scaled(unitPrice, quantity) : -1,
          );
          final lineTotal = _analyticsInt(line['totalMinorUnits'], -1);
          final lineCost = _analyticsInt(line['costTotalMinorUnits'], -1);

          if ((lineStoreId is String && lineStoreId != context.storeId) ||
              id.isEmpty ||
              productId.isEmpty ||
              description.isEmpty ||
              !lineIds.add(id) ||
              quantity <= 0 ||
              unitPrice < 0 ||
              discount < 0 ||
              gross < 0 ||
              lineTotal < 0 ||
              lineCost < 0 ||
              discount > gross ||
              gross - discount != lineTotal ||
              (returnedQuantityByLine[id] ?? 0) > quantity) {
            return FailureResult<List<SalesInvoiceDocument>>(
              ValidationFailure(
                'Sale $invoiceId contains invalid invoice line data.',
              ),
            );
          }

          verifiedSubtotal += lineTotal;
          verifiedCost += lineCost;
          lines.add(SalesInvoiceLineSummary(
            id: id,
            productId: productId,
            description: description,
            quantityMilliUnits: quantity,
            unitPrice: Money(minorUnits: unitPrice, currency: currency),
            discount: Money(minorUnits: discount, currency: currency),
            total: Money(minorUnits: lineTotal, currency: currency),
            cost: Money(minorUnits: lineCost, currency: currency),
            returnedQuantityMilliUnits: returnStatus == 'full' &&
                    returnedQuantityByLine.isEmpty
                ? quantity
                : (returnedQuantityByLine[id] ?? 0),
            unitName: _analyticsNullableString(line['unitName']),
            isService: line['isService'] == true,
          ));
        }

        if (verifiedSubtotal != subtotal || verifiedCost != cost) {
          return FailureResult<List<SalesInvoiceDocument>>(
            ValidationFailure(
              'Sale $invoiceId lines do not reconcile to posted totals.',
            ),
          );
        }

        documents.add(SalesInvoiceDocument(
          invoice: invoice,
          lines: List.unmodifiable(lines),
        ));
      }

      return Success<List<SalesInvoiceDocument>>(
        List.unmodifiable(documents),
      );
    } on FirebaseException catch (error) {
      return FailureResult<List<SalesInvoiceDocument>>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } catch (error) {
      return FailureResult<List<SalesInvoiceDocument>>(
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
      final returnsPageFuture = _readPeriodDocuments(
        collection: FirebasePaths.salesReturns(_firestore, context.storeId),
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
      final returnsPage = await returnsPageFuture;

      // Historical V2 sales keep their lines only in a subcollection.
      // Read these in bounded batches. Never silently publish partial
      // product/category results if the legacy recovery would be too costly.
      final legacySales = salesPage.documents.where((snapshot) {
        return snapshot.data()?['lines'] is! List;
      }).toList(growable: false);
      if (legacySales.length > 200) {
        return const FailureResult<SalesAnalytics>(
          ValidationFailure(
            'Historical sale lines exceed the safe report read limit. '
            'Narrow the period or perform a verified line-snapshot migration.',
          ),
        );
      }
      final recoveredLines = <String, List<Map<String, dynamic>>>{};
      for (var offset = 0; offset < legacySales.length; offset += 20) {
        final batchEnd =
            offset + 20 < legacySales.length ? offset + 20 : legacySales.length;
        final batch = legacySales.sublist(offset, batchEnd);
        final lines = await Future.wait(
          batch.map((invoice) => invoice.reference.collection('lines').get()),
        );
        for (var index = 0; index < batch.length; index++) {
          recoveredLines[batch[index].id] = [
            for (final item in lines[index].docs) item.data(),
          ];
        }
      }

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

      void ensureCurrency(String transactionCurrency) {
        if (currency == null) {
          currency = transactionCurrency;
          salesRevenue = Money.zero(currency: transactionCurrency);
          salesCost = Money.zero(currency: transactionCurrency);
          return;
        }
        if (transactionCurrency != currency) {
          throw const FormatException(
            'Sales analytics cannot combine different currencies.',
          );
        }
      }

      void applyLine({
        required Map<String, dynamic> line,
        required String rowCurrency,
        required int sign,
      }) {
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
        final storedBaseQuantity = _analyticsInt(
          line['baseQuantityMilliUnits'],
          -1,
        );
        final baseQuantityMilliUnits = storedBaseQuantity >= 0
            ? storedBaseQuantity
            : _scaled(quantityMilliUnits, factorMilliUnits);
        final lineRevenueMinorUnits = _analyticsInt(
          line['totalMinorUnits'],
          _nonNegative(
            _scaled(
                  _analyticsInt(line['unitPriceMinorUnits']),
                  quantityMilliUnits,
                ) -
                _analyticsInt(line['discountMinorUnits']),
          ),
        );
        final isService =
            line['isService'] is bool && line['isService'] as bool;
        final lineCostMinorUnits = _analyticsInt(
          line['costTotalMinorUnits'],
          isService
              ? 0
              : _scaled(
                  _analyticsInt(line['unitCostMinorUnits']),
                  baseQuantityMilliUnits,
                ),
        );

        _addAnalyticsRow(
          productRows,
          key: productId ?? fallbackLabel,
          label: productLabel,
          quantityMilliUnits: sign * baseQuantityMilliUnits,
          revenueMinorUnits: sign * lineRevenueMinorUnits,
          costMinorUnits: sign * lineCostMinorUnits,
          currency: rowCurrency,
        );
        _addAnalyticsRow(
          categoryRows,
          key: categoryId,
          label: categoryLabel,
          quantityMilliUnits: sign * baseQuantityMilliUnits,
          revenueMinorUnits: sign * lineRevenueMinorUnits,
          costMinorUnits: sign * lineCostMinorUnits,
          currency: rowCurrency,
        );
      }

      for (final document in salesPage.documents) {
        final data = document.data() ?? const <String, dynamic>{};
        final postedAt = _analyticsDate(data['postedAt']);
        if (postedAt == null ||
            data['storeId'] != context.storeId ||
            data['status'] != 'posted') {
          return FailureResult<SalesAnalytics>(
            ValidationFailure(
              'Sale ${document.id} has invalid tenant, status, or date.',
            ),
          );
        }

        final saleCurrency = _analyticsString(data['currency'], 'ILS');
        try {
          ensureCurrency(saleCurrency);
        } on FormatException catch (error) {
          return FailureResult<SalesAnalytics>(
            ValidationFailure(error.message.toString()),
          );
        }

        final saleTotalMinorUnits = _analyticsInt(
          data['totalMinorUnits'],
          _analyticsInt(data['amountMinorUnits']),
        );
        final taxMinorUnits = _analyticsInt(data['taxMinorUnits']);
        final expectedSubtotal = _analyticsInt(
          data['subtotalMinorUnits'],
          saleTotalMinorUnits - taxMinorUnits,
        );
        final saleCostMinorUnits = _analyticsInt(data['costTotalMinorUnits']);
        if (saleTotalMinorUnits < 0 ||
            taxMinorUnits < 0 ||
            expectedSubtotal < 0 ||
            saleCostMinorUnits < 0 ||
            expectedSubtotal + taxMinorUnits != saleTotalMinorUnits) {
          return FailureResult<SalesAnalytics>(
            ValidationFailure('Sale ${document.id} has invalid totals.'),
          );
        }

        final rawLines = data['lines'] ?? recoveredLines[document.id];
        if (rawLines is! List || rawLines.isEmpty) {
          return FailureResult<SalesAnalytics>(
            ValidationFailure(
              'Sale ${document.id} has no verifiable invoice lines.',
            ),
          );
        }
        var verifiedSubtotal = 0;
        var verifiedCost = 0;
        for (final rawLine in rawLines) {
          if (rawLine is! Map) {
            return FailureResult<SalesAnalytics>(
              ValidationFailure(
                'Sale ${document.id} has malformed invoice lines.',
              ),
            );
          }
          final line = Map<String, dynamic>.from(rawLine);
          final quantityMilliUnits = _analyticsInt(line['quantityMilliUnits']);
          final lineRevenueMinorUnits = _analyticsInt(
            line['totalMinorUnits'],
            -1,
          );
          final lineCostMinorUnits = _analyticsInt(
            line['costTotalMinorUnits'],
            -1,
          );
          if (quantityMilliUnits <= 0 ||
              lineRevenueMinorUnits < 0 ||
              lineCostMinorUnits < 0) {
            return FailureResult<SalesAnalytics>(
              ValidationFailure(
                'Sale ${document.id} contains invalid invoice line totals.',
              ),
            );
          }
          verifiedSubtotal += lineRevenueMinorUnits;
          verifiedCost += lineCostMinorUnits;
          applyLine(line: line, rowCurrency: saleCurrency, sign: 1);
        }
        if (verifiedSubtotal != expectedSubtotal ||
            verifiedCost != saleCostMinorUnits) {
          return FailureResult<SalesAnalytics>(
            ValidationFailure(
              'Sale ${document.id} lines do not match posted totals.',
            ),
          );
        }

        salesRevenue += Money(
          minorUnits: expectedSubtotal,
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
          revenueMinorUnits: expectedSubtotal,
          costMinorUnits: saleCostMinorUnits,
          currency: saleCurrency,
        );
      }

      // Returns affect the period in which the return was posted. They do not
      // rewrite the original sale period. Full-return documents carry the
      // immutable original line snapshot so product/category analytics can be
      // reversed using the exact posted revenue and COGS amounts.
      for (final document in returnsPage.documents) {
        final data = document.data() ?? const <String, dynamic>{};
        final returnType = data['returnType'];
        if (data['storeId'] != context.storeId ||
            data['status'] != 'posted' ||
            (returnType != 'full' && returnType != 'partial') ||
            _analyticsDate(data['postedAt']) == null) {
          return FailureResult<SalesAnalytics>(
            ValidationFailure(
              'Sale return ${document.id} has invalid tenant or status.',
            ),
          );
        }
        final returnCurrency = _analyticsString(data['currency'], 'ILS');
        try {
          ensureCurrency(returnCurrency);
        } on FormatException catch (error) {
          return FailureResult<SalesAnalytics>(
            ValidationFailure(error.message.toString()),
          );
        }

        final subtotal = _analyticsInt(data['subtotalMinorUnits'], -1);
        final tax = _analyticsInt(data['taxMinorUnits'], -1);
        final total = _analyticsInt(data['totalMinorUnits'], -1);
        final returnedCost = _analyticsInt(data['costTotalMinorUnits'], -1);
        if (subtotal < 0 ||
            tax < 0 ||
            total < 0 ||
            returnedCost < 0 ||
            subtotal + tax != total) {
          return FailureResult<SalesAnalytics>(
            ValidationFailure(
              'Sale return ${document.id} has invalid totals.',
            ),
          );
        }

        final rawLines = data['lines'];
        if (rawLines is! List || rawLines.isEmpty) {
          return FailureResult<SalesAnalytics>(
            ValidationFailure(
              'Sale return ${document.id} has no immutable line snapshot.',
            ),
          );
        }
        var verifiedSubtotal = 0;
        var verifiedCost = 0;
        for (final rawLine in rawLines) {
          if (rawLine is! Map) {
            return FailureResult<SalesAnalytics>(
              ValidationFailure(
                'Sale return ${document.id} has malformed lines.',
              ),
            );
          }
          final line = Map<String, dynamic>.from(rawLine);
          final lineRevenue = _analyticsInt(line['totalMinorUnits'], -1);
          final lineCost = _analyticsInt(line['costTotalMinorUnits'], -1);
          final quantity = _analyticsInt(line['quantityMilliUnits'], -1);
          if (lineRevenue < 0 || lineCost < 0 || quantity <= 0) {
            return FailureResult<SalesAnalytics>(
              ValidationFailure(
                'Sale return ${document.id} contains invalid line totals.',
              ),
            );
          }
          verifiedSubtotal += lineRevenue;
          verifiedCost += lineCost;
          applyLine(line: line, rowCurrency: returnCurrency, sign: -1);
        }
        if (verifiedSubtotal != subtotal || verifiedCost != returnedCost) {
          return FailureResult<SalesAnalytics>(
            ValidationFailure(
              'Sale return ${document.id} lines do not match return totals.',
            ),
          );
        }

        salesRevenue -= Money(minorUnits: subtotal, currency: returnCurrency);
        salesCost -= Money(minorUnits: returnedCost, currency: returnCurrency);

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
          revenueMinorUnits: -subtotal,
          costMinorUnits: -returnedCost,
          currency: returnCurrency,
        );
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
          mayBeTruncated:
              salesPage.mayBeTruncated || returnsPage.mayBeTruncated,
        ),
      );
    } on FirebaseException catch (error) {
      return FailureResult<SalesAnalytics>(
        InfrastructureFailure(error.message ?? error.code),
      );
    } on FormatException catch (error) {
      return FailureResult<SalesAnalytics>(
        ValidationFailure(error.message.toString()),
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
      final currentPageSize = remaining < pageSize ? remaining : pageSize;
      Query<Map<String, dynamic>> query = collection
          .where('postedAt', isGreaterThanOrEqualTo: start)
          .where('postedAt', isLessThanOrEqualTo: end)
          .orderBy('postedAt')
          .limit(currentPageSize);
      if (cursor != null) {
        query = query.startAfterDocument(cursor);
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
            .startAfterDocument(cursor)
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

class _PagedDocuments {
  const _PagedDocuments({
    required this.documents,
    required this.mayBeTruncated,
  });

  final List<DocumentSnapshot<Map<String, dynamic>>> documents;
  final bool mayBeTruncated;
}
