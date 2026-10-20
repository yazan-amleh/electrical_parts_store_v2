import 'dart:typed_data';

import '../entities/operational_report.dart';
import '../entities/sales_analytics.dart';

abstract interface class ReportDocumentBuilder {
  Future<Uint8List> buildOperationalReport({
    required OperationalReport report,
    required String storeName,
  });

  Future<Uint8List> buildSalesAnalyticsReport({
    required SalesAnalytics analytics,
    required String storeName,
  });
}
