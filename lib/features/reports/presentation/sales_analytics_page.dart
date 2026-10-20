import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../../../core/money/money.dart';
import '../../../core/quantity/quantity.dart';
import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../domain/entities/sales_analytics.dart';
import '../domain/repositories/reports_repository.dart';
import '../domain/services/report_document_builder.dart';

class SalesAnalyticsPage extends StatefulWidget {
  const SalesAnalyticsPage({
    required this.repository,
    required this.documentBuilder,
    required this.user,
    required this.membership,
    super.key,
  });

  final ReportsRepository? repository;
  final ReportDocumentBuilder? documentBuilder;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<SalesAnalyticsPage> createState() => _SalesAnalyticsPageState();
}

class _SalesAnalyticsPageState extends State<SalesAnalyticsPage> {
  late DateTime _from;
  late DateTime _to;
  SalesAnalytics? _analytics;
  bool _isLoading = true;
  bool _isExporting = false;
  String? _errorMessage;

  StoreContext get _context {
    return StoreContext(
      storeId: widget.membership.storeId,
      userId: widget.user.id,
    );
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month, now.day, 23, 59, 59);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.repository == null) {
      return const Center(
        child: Text('مستودع تحليلات المبيعات غير موصول بهذه البيئة.'),
      );
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_analytics == null || _errorMessage != null) {
      return _buildErrorState();
    }

    final analytics = _analytics!;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _buildHeader(context),
            if (analytics.mayBeTruncated) ...[
              const SizedBox(height: 12),
              _buildWarning(context),
            ],
            const SizedBox(height: 12),
            _buildMetrics(context, analytics),
            const SizedBox(height: 12),
            _buildPaymentMethods(context, analytics),
            const SizedBox(height: 12),
            _buildRanking(
              context,
              title: 'الأصناف الأكثر مبيعاً',
              rows: analytics.productRows,
              showQuantity: true,
            ),
            const SizedBox(height: 12),
            _buildRanking(
              context,
              title: 'المبيعات حسب التصنيف',
              rows: analytics.categoryRows,
              showQuantity: true,
            ),
            const SizedBox(height: 12),
            _buildRanking(
              context,
              title: 'المبيعات حسب العميل',
              rows: analytics.customerRows,
              showQuantity: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.trending_up_outlined, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'تحليلات المبيعات',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'تحديث',
                  onPressed: _isLoading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'التجميع مبني على فواتير البيع المرحّلة. الربح الإجمالي '
              'يستخدم تكلفة السطور المسجلة وقت البيع.',
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _dateButton(
                  context,
                  label: 'من',
                  date: _from,
                  onPressed: _pickFrom,
                ),
                _dateButton(
                  context,
                  label: 'إلى',
                  date: _to,
                  onPressed: _pickTo,
                ),
                FilledButton.icon(
                  onPressed: _isLoading ? null : _load,
                  icon: const Icon(Icons.filter_alt_outlined),
                  label: const Text('تطبيق الفترة'),
                ),
                OutlinedButton.icon(
                  onPressed: _analytics == null ? null : _copyCsv,
                  icon: const Icon(Icons.content_copy_outlined),
                  label: const Text('نسخ CSV'),
                ),
                OutlinedButton.icon(
                  onPressed: _analytics == null ||
                          widget.documentBuilder == null ||
                          _isExporting
                      ? null
                      : () => _runPdfExport(share: false),
                  icon: const Icon(Icons.print_outlined),
                  label: Text(
                    _isExporting ? 'جارٍ تجهيز PDF...' : 'PDF / طباعة',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _analytics == null ||
                          widget.documentBuilder == null ||
                          _isExporting
                      ? null
                      : () => _runPdfExport(share: true),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('مشاركة PDF'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateButton(
    BuildContext context, {
    required String label,
    required DateTime date,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.calendar_today_outlined),
      label: Text('$label: ${_formatDate(date)}'),
    );
  }

  Widget _buildWarning(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_outlined,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'وصلت تحليلات المبيعات إلى سقف الأمان لعدد الفواتير المقروءة. '
                'قد تكون النتائج ناقصة؛ ضيّق الفترة أو قسّمها قبل اعتمادها.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetrics(BuildContext context, SalesAnalytics analytics) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _metricCard(
          context,
          title: 'إجمالي المبيعات',
          value: analytics.salesRevenue,
          subtitle: '${analytics.salesCount} فاتورة',
          icon: Icons.point_of_sale_outlined,
        ),
        _metricCard(
          context,
          title: 'التكلفة',
          value: analytics.salesCost,
          subtitle: 'من تكلفة السطور',
          icon: Icons.inventory_2_outlined,
        ),
        _metricCard(
          context,
          title: 'مجمل الربح',
          value: analytics.grossProfit,
          subtitle: 'المبيعات ناقص التكلفة',
          icon: Icons.trending_up_outlined,
        ),
      ],
    );
  }

  Widget _metricCard(
    BuildContext context, {
    required String title,
    required Money value,
    required String subtitle,
    required IconData icon,
  }) {
    return SizedBox(
      width: 270,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(child: Icon(icon)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value.formatted,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentMethods(BuildContext context, SalesAnalytics analytics) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('طرق الدفع', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (analytics.paymentMethodCounts.isEmpty)
              const Text('لا توجد فواتير ضمن الفترة.')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in analytics.paymentMethodCounts.entries)
                    Chip(
                      avatar: const Icon(Icons.payments_outlined, size: 18),
                      label: Text(
                        '${_paymentLabel(entry.key)}: ${entry.value}',
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRanking(
    BuildContext context, {
    required String title,
    required List<SalesAnalyticsRow> rows,
    required bool showQuantity,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              const Text('لا توجد بيانات ضمن الفترة.')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    const DataColumn(label: Text('الاسم')),
                    if (showQuantity) const DataColumn(label: Text('الكمية')),
                    const DataColumn(label: Text('المبيعات')),
                    const DataColumn(label: Text('التكلفة')),
                    const DataColumn(label: Text('مجمل الربح')),
                  ],
                  rows: [
                    for (final row in rows.take(25))
                      DataRow(
                        cells: [
                          DataCell(
                            SizedBox(width: 220, child: Text(row.label)),
                          ),
                          if (showQuantity)
                            DataCell(
                              Text(
                                Quantity.fromMilliUnits(
                                  row.quantityMilliUnits,
                                ).formatted,
                              ),
                            ),
                          DataCell(Text(row.revenue.formatted)),
                          DataCell(Text(row.cost.formatted)),
                          DataCell(Text(row.grossProfit.formatted)),
                        ],
                      ),
                  ],
                ),
              ),
            if (rows.length > 25)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'يظهر أول 25 نتيجة مرتبة حسب قيمة المبيعات.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          Text(
            _errorMessage ?? 'تعذر تحميل تحليلات المبيعات.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    final repository = widget.repository;
    if (repository == null) {
      return;
    }
    if (_from.isAfter(_to)) {
      setState(() => _errorMessage = 'بداية الفترة يجب أن تسبق نهايتها.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final result = await repository.getSalesAnalytics(
      context: _context,
      from: _from,
      to: _to,
    );
    if (!mounted) {
      return;
    }
    if (result is FailureResult<SalesAnalytics>) {
      setState(() {
        _isLoading = false;
        _errorMessage = result.failure.message;
      });
      return;
    }
    setState(() {
      _analytics = (result as Success<SalesAnalytics>).value;
      _isLoading = false;
    });
  }

  Future<void> _runPdfExport({required bool share}) async {
    final analytics = _analytics;
    final builder = widget.documentBuilder;
    if (analytics == null || builder == null) {
      _showMessage('تصدير PDF غير موصول بهذه البيئة.');
      return;
    }

    setState(() => _isExporting = true);
    try {
      final bytes = await builder.buildSalesAnalyticsReport(
        analytics: analytics,
        storeName: widget.membership.storeId,
      );
      final filename =
          'sales_analytics_' + _formatDate(_from) + '_' + _formatDate(_to);
      if (share) {
        await Printing.sharePdf(bytes: bytes, filename: filename + '.pdf');
      } else {
        await Printing.layoutPdf(onLayout: (_) async => bytes);
      }
    } catch (error) {
      _showMessage('تعذر تجهيز PDF: ' + error.toString());
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyCsv() async {
    final analytics = _analytics;
    if (analytics == null) {
      return;
    }

    final rows = <String>[
      'group,name,quantity,sales,cost,gross_profit,currency',
      for (final row in [
        ...analytics.productRows.map((value) => ('product', value)),
        ...analytics.categoryRows.map((value) => ('category', value)),
        ...analytics.customerRows.map((value) => ('customer', value)),
      ])
        [
          _csvValue(row.$1),
          _csvValue(row.$2.label),
          row.$2.quantityMilliUnits.toString(),
          row.$2.revenue.minorUnits.toString(),
          row.$2.cost.minorUnits.toString(),
          row.$2.grossProfit.minorUnits.toString(),
          _csvValue(row.$2.revenue.currency),
        ].join(','),
    ];
    await Clipboard.setData(ClipboardData(text: rows.join('\n')));
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('تم نسخ تحليلات المبيعات بصيغة CSV.')),
        );
    }
  }

  String _csvValue(String value) {
    return '"${value.replaceAll('"', '""')}"';
  }

  Future<void> _pickFrom() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      _from = DateTime(selected.year, selected.month, selected.day);
      if (_from.isAfter(_to)) {
        _to = DateTime(selected.year, selected.month, selected.day, 23, 59, 59);
      }
    });
  }

  Future<void> _pickTo() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      _to = DateTime(selected.year, selected.month, selected.day, 23, 59, 59);
    });
  }

  String _formatDate(DateTime date) {
    final utc = date.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
  }

  String _paymentLabel(String value) {
    switch (value) {
      case 'cash':
        return 'نقدي';
      case 'bank':
        return 'بنك';
      case 'card':
        return 'بطاقة';
      case 'credit':
        return 'آجل';
      case 'cheque':
        return 'شيك';
      case 'unknown':
        return 'غير محدد';
      default:
        return value;
    }
  }
}
