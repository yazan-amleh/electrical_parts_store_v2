import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../entities/operational_report.dart';
import '../entities/sales_analytics.dart';
import '../entities/sales_invoice_report.dart';

abstract interface class ReportsRepository {
  Future<Result<OperationalReport>> getOperationalReport({
    required StoreContext context,
    required DateTime from,
    required DateTime to,
    int limit = 500,
    int maxDocuments = 10000,
  });

  Future<Result<SalesInvoiceReport>> getSalesInvoices({
    required StoreContext context,
    required DateTime from,
    required DateTime to,
    int limit = 250,
    int maxDocuments = 1000,
  });

  Future<Result<List<SalesInvoiceDocument>>> getSalesInvoiceDocuments({
    required StoreContext context,
    required List<String> invoiceIds,
    int maxInvoices = 100,
  });

  Future<Result<SalesAnalytics>> getSalesAnalytics({
    required StoreContext context,
    required DateTime from,
    required DateTime to,
    int limit = 500,
    int maxDocuments = 10000,
  });
}
