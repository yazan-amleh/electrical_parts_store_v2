import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../../../core/idempotency/idempotency_key.dart';
import '../../../core/money/money.dart';
import '../../../core/quantity/quantity.dart';
import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../../auth/domain/enums/store_role.dart';
import '../../sales/domain/entities/sale_return.dart';
import '../../sales/domain/repositories/sale_repository.dart';
import '../domain/entities/sales_analytics.dart';
import '../domain/entities/sales_invoice_report.dart';
import '../domain/repositories/reports_repository.dart';
import '../domain/services/report_document_builder.dart';
import 'sales_excel_export.dart';
import 'sales_invoice_selection_export.dart';

class SalesAnalyticsPage extends StatefulWidget {
  const SalesAnalyticsPage({
    required this.repository,
    required this.documentBuilder,
    required this.saleRepository,
    required this.user,
    required this.membership,
    super.key,
  });

  final ReportsRepository? repository;
  final ReportDocumentBuilder? documentBuilder;
  final SaleRepository? saleRepository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<SalesAnalyticsPage> createState() => _SalesAnalyticsPageState();
}

class _SalesAnalyticsPageState extends State<SalesAnalyticsPage> {
  late DateTime _from;
  late DateTime _to;
  SalesAnalytics? _analytics;
  SalesInvoiceReport? _invoices;
  String? _invoiceError;
  final _searchController = TextEditingController();
  final _selectedInvoiceIds = <String>{};
  final _invoiceSelectionExport = const SalesInvoiceSelectionExport();
  final _salesExcelExport = const SalesExcelExport();
  bool _selectionMode = false;
  int _selectedTab = 0;
  int _reportEpoch = 0;
  bool _isLoading = true;
  bool _isExporting = false;
  String? _returningInvoiceId;
  final Map<String, SaleReturn> _pendingFullReturns = <String, SaleReturn>{};
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
  void didUpdateWidget(covariant SalesAnalyticsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.id != widget.user.id ||
        oldWidget.membership.storeId != widget.membership.storeId) {
      _analytics = null;
      _invoices = null;
      _searchController.clear();
      _selectedInvoiceIds.clear();
      _pendingFullReturns.clear();
      _selectionMode = false;
      _load();
    }
  }

  @override
  void dispose() {
    ++_reportEpoch;
    _searchController.dispose();
    super.dispose();
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
            DefaultTabController(
              length: 3,
              initialIndex: _selectedTab,
              child: TabBar(
                isScrollable: true,
                onTap: (tab) => setState(() => _selectedTab = tab),
                tabs: const [
                  Tab(text: 'تفاصيل المبيعات', icon: Icon(Icons.receipt_long)),
                  Tab(
                      text: 'الأصناف الأكثر مبيعاً',
                      icon: Icon(Icons.inventory_2)),
                  Tab(text: 'ملخص العملاء', icon: Icon(Icons.groups_outlined)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'بحث في التبويب الحالي',
                hintText: 'رقم الفاتورة، العميل أو الصنف',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            if (_selectedTab == 0) ...[
              _buildInvoiceSelectionToolbar(context, analytics),
              _buildInvoiceDetails(context, analytics),
            ] else if (_selectedTab == 1) ...[
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
            ] else ...[
              _buildRanking(
                context,
                title: 'ملخص العملاء',
                rows: analytics.customerRows,
                showQuantity: false,
              ),
              const SizedBox(height: 12),
              _buildPaymentMethods(context, analytics),
            ],
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
              'التجميع مبني على فواتير البيع والمردودات المرحّلة ضمن '
              'الفترة. المردود يخفض صافي المبيعات والتكلفة في تاريخ '
              'ترحيل الإرجاع دون تغيير فترة البيع الأصلية.',
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
                  onPressed:
                      _analytics == null || _isExporting ? null : _exportXlsx,
                  icon: const Icon(Icons.table_view_outlined),
                  label: const Text('تصدير XLSX'),
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
                  onPressed: _analytics == null ||
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
          title: 'صافي المبيعات',
          value: analytics.salesRevenue,
          subtitle: '${analytics.salesCount} فاتورة بيع قبل احتساب المردودات',
          icon: Icons.point_of_sale_outlined,
        ),
        _metricCard(
          context,
          title: 'صافي تكلفة المبيعات',
          value: analytics.salesCost,
          subtitle: 'بعد عكس تكلفة الأصناف المرتجعة',
          icon: Icons.inventory_2_outlined,
        ),
        _metricCard(
          context,
          title: 'مجمل الربح',
          value: analytics.grossProfit,
          subtitle: 'صافي المبيعات ناقص صافي التكلفة',
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

  List<SalesInvoiceSummary> _matchingInvoices(
    SalesInvoiceReport report,
    SalesAnalytics analytics,
  ) {
    final names = {
      for (final row in analytics.customerRows) row.key: row.label,
    };
    final query = _searchController.text.trim().toLowerCase();
    return report.invoices.where((invoice) {
      final customer =
          names[invoice.customerId] ?? invoice.customerId ?? 'بدون عميل';
      return query.isEmpty ||
          invoice.id.toLowerCase().contains(query) ||
          customer.toLowerCase().contains(query) ||
          (invoice.description?.toLowerCase().contains(query) ?? false);
    }).toList(growable: false);
  }

  void _toggleInvoice(String id, bool selected) {
    setState(() {
      if (selected) {
        if (_selectedInvoiceIds.length >= 100) {
          _showMessage('يمكن اختيار 100 فاتورة كحد أقصى لكل عملية طباعة.');
          return;
        }
        _selectedInvoiceIds.add(id);
      } else {
        _selectedInvoiceIds.remove(id);
      }
    });
  }

  Widget _buildInvoiceSelectionToolbar(
    BuildContext context,
    SalesAnalytics analytics,
  ) {
    final report = _invoices;
    if (report == null) return const SizedBox.shrink();
    final matching = _matchingInvoices(report, analytics);
    final chosenCount = _selectedInvoiceIds.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: _isExporting
                ? null
                : () => setState(() {
                      _selectionMode = !_selectionMode;
                      if (!_selectionMode) _selectedInvoiceIds.clear();
                    }),
            icon: Icon(_selectionMode ? Icons.close : Icons.checklist_outlined),
            label: Text(_selectionMode ? 'إنهاء التحديد' : 'اختيار عدة فواتير'),
          ),
          if (_selectionMode) ...[
            Text('$chosenCount فاتورة مختارة'),
            TextButton(
              onPressed: _isExporting
                  ? null
                  : () => setState(() {
                        _selectedInvoiceIds.addAll(
                          matching.take(100).map((item) => item.id),
                        );
                      }),
              child: const Text('تحديد أول 100 مطابقة'),
            ),
            TextButton(
              onPressed: _isExporting || chosenCount == 0
                  ? null
                  : () => setState(_selectedInvoiceIds.clear),
              child: const Text('إلغاء التحديد'),
            ),
            FilledButton.icon(
              onPressed: _isExporting || chosenCount == 0
                  ? null
                  : () => _exportSelectedInvoices(print: true),
              icon: const Icon(Icons.print_outlined),
              label: const Text('طباعة المحدد'),
            ),
            OutlinedButton.icon(
              onPressed: _isExporting || chosenCount == 0
                  ? null
                  : () => _exportSelectedInvoices(print: false),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('مشاركة PDF للمحدد'),
            ),
            TextButton.icon(
              onPressed: _isExporting || chosenCount == 0
                  ? null
                  : _copySelectedInvoices,
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('نسخ CSV للمحدد'),
            ),
          ],
          if (report.mayBeTruncated)
            const Text(
              'التحديد لا يشمل الفواتير خارج سقف التحميل.',
              style: TextStyle(color: Colors.deepOrange),
            ),
        ],
      ),
    );
  }

  List<SalesInvoiceSummary> _selectedInvoices() {
    final report = _invoices;
    if (report == null) return const [];
    return report.invoices
        .where((invoice) => _selectedInvoiceIds.contains(invoice.id))
        .take(100)
        .toList(growable: false);
  }

  Map<String, String> _customerNames() => {
        for (final row in _analytics?.customerRows ?? <SalesAnalyticsRow>[])
          row.key: row.label,
      };

  Future<void> _exportSelectedInvoices({required bool print}) async {
    final invoices = _selectedInvoices();
    await _exportInvoiceDocuments(invoices, print: print);
  }

  Future<void> _exportInvoiceDocument(
    SalesInvoiceSummary invoice, {
    required bool print,
  }) async {
    await _exportInvoiceDocuments([invoice], print: print);
  }

  Future<void> _exportInvoiceDocuments(
    List<SalesInvoiceSummary> invoices, {
    required bool print,
  }) async {
    final repository = widget.repository;
    if (_isExporting || invoices.isEmpty || repository == null) return;
    setState(() => _isExporting = true);
    final requestedStore = widget.membership.storeId;
    final requestedUser = widget.user.id;
    try {
      final result = await repository.getSalesInvoiceDocuments(
        context: _context,
        invoiceIds: invoices.map((invoice) => invoice.id).toList(),
        maxInvoices: 100,
      );
      if (!mounted ||
          requestedStore != widget.membership.storeId ||
          requestedUser != widget.user.id) {
        return;
      }
      if (result is FailureResult<List<SalesInvoiceDocument>>) {
        _showMessage(
          'تعذر تحميل سطور الفاتورة: ${result.failure.message}',
        );
        return;
      }

      final documents = (result as Success<List<SalesInvoiceDocument>>).value;
      final bytes = await _invoiceSelectionExport.invoicePdf(
        documents: documents,
        customerNames: _customerNames(),
        storeLabel: requestedStore,
      );
      if (!mounted ||
          requestedStore != widget.membership.storeId ||
          requestedUser != widget.user.id) {
        return;
      }
      if (print) {
        await Printing.layoutPdf(onLayout: (_) async => bytes);
      } else {
        final filename = documents.length == 1
            ? 'sale_invoice_${documents.first.invoice.id}.pdf'
            : 'selected_sales_invoices.pdf';
        await Printing.sharePdf(bytes: bytes, filename: filename);
      }
    } catch (_) {
      if (mounted) _showMessage('تعذر تجهيز الفاتورة التفصيلية.');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _copySelectedInvoices() async {
    final invoices = _selectedInvoices();
    if (invoices.isEmpty) return;
    try {
      await Clipboard.setData(
        ClipboardData(
          text: _invoiceSelectionExport.csv(
            invoices: invoices,
            customerNames: _customerNames(),
          ),
        ),
      );
      if (mounted) _showMessage('تم نسخ الفواتير المختارة بصيغة CSV.');
    } catch (_) {
      if (mounted) _showMessage('تعذر نسخ الفواتير المختارة.');
    }
  }

  Widget _buildInvoiceDetails(
    BuildContext context,
    SalesAnalytics analytics,
  ) {
    if (_invoiceError != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'تعذر تحميل تفاصيل الفواتير: $_invoiceError',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }
    final report = _invoices;
    if (report == null) {
      return const Center(child: Text('لم تُحمّل تفاصيل الفواتير.'));
    }
    final customerNames = {
      for (final row in analytics.customerRows) row.key: row.label,
    };
    final invoices = _matchingInvoices(report, analytics);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('تفاصيل المبيعات',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'يعرض الفواتير المرحّلة المحمّلة فقط. الأرقام والضرائب '
              'تُقرأ من المستندات المحاسبية، وليست إعادة احتساب للتسويات.',
            ),
            if (report.mayBeTruncated)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'تنبيه: تجاوز عدد الفواتير سقف التحميل؛ القائمة والبحث '
                  'والتصدير لا تشمل بقية الفواتير. ضيّق الفترة.',
                  style: TextStyle(color: Colors.deepOrange),
                ),
              ),
            const SizedBox(height: 10),
            Text('${invoices.length} فاتورة مطابقة من '
                '${report.invoices.length} فاتورة محمّلة'),
            if (invoices.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('لا توجد فواتير مطابقة في البيانات المحمّلة.'),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  showCheckboxColumn: _selectionMode,
                  columns: const [
                    DataColumn(label: Text('رقم الفاتورة')),
                    DataColumn(label: Text('التاريخ')),
                    DataColumn(label: Text('العميل')),
                    DataColumn(label: Text('الدفع')),
                    DataColumn(label: Text('قبل الضريبة')),
                    DataColumn(label: Text('الضريبة')),
                    DataColumn(label: Text('الإجمالي')),
                    DataColumn(label: Text('الحالة')),
                    DataColumn(label: Text('مرجع القيد')),
                    DataColumn(label: Text('إجراءات')),
                  ],
                  rows: [
                    for (final item in invoices.take(100))
                      DataRow(
                          selected: _selectedInvoiceIds.contains(item.id),
                          onSelectChanged: !_selectionMode
                              ? null
                              : (value) =>
                                  _toggleInvoice(item.id, value == true),
                          cells: [
                            DataCell(SelectableText(item.id)),
                            DataCell(Text(_formatDate(item.postedAt))),
                            DataCell(Text(
                              customerNames[item.customerId] ??
                                  item.customerId ??
                                  'بدون عميل',
                            )),
                            DataCell(Text(_paymentLabel(item.paymentMethod))),
                            DataCell(Text(item.subtotal.formatted)),
                            DataCell(Text(item.tax.formatted)),
                            DataCell(Text(item.total.formatted)),
                            DataCell(
                              Chip(
                                avatar: Icon(
                                  item.isFullyReturned
                                      ? Icons.undo
                                      : Icons.check_circle_outline,
                                  size: 16,
                                ),
                                label: Text(
                                  item.isFullyReturned
                                      ? 'مُرجعة بالكامل'
                                      : 'مرحّلة',
                                ),
                              ),
                            ),
                            DataCell(SelectableText(item.journalEntryId)),
                            DataCell(Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'طباعة الفاتورة ${item.id}',
                                  onPressed: _isExporting
                                      ? null
                                      : () => _exportInvoiceDocument(
                                            item,
                                            print: true,
                                          ),
                                  icon: const Icon(Icons.print_outlined),
                                ),
                                IconButton(
                                  tooltip: 'مشاركة PDF للفاتورة ${item.id}',
                                  onPressed: _isExporting
                                      ? null
                                      : () => _exportInvoiceDocument(
                                            item,
                                            print: false,
                                          ),
                                  icon: const Icon(
                                    Icons.picture_as_pdf_outlined,
                                  ),
                                ),
                                IconButton(
                                  tooltip: item.isFullyReturned
                                      ? 'الفاتورة مُرجعة بالكامل'
                                      : 'إرجاع الفاتورة بالكامل',
                                  onPressed: _canReturnInvoice(item)
                                      ? () => _returnFullInvoice(item)
                                      : null,
                                  icon: _returningInvoiceId == item.id
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.undo_outlined),
                                ),
                              ],
                            )),
                          ]),
                  ],
                ),
              ),
            if (invoices.length > 100)
              const Text(
                'تظهر أول 100 فاتورة مطابقة. نسخ CSV يشمل جميع '
                'الفواتير المحمّلة والمطابقة للبحث، وليس المعروضة فقط.',
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
                    for (final row in rows
                        .where((row) => row.label.toLowerCase().contains(
                              _searchController.text.trim().toLowerCase(),
                            ))
                        .take(25))
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

    final epoch = ++_reportEpoch;
    final requestedStore = widget.membership.storeId;
    final requestedUser = widget.user.id;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _invoiceError = null;
      _invoices = null;
      _selectedInvoiceIds.clear();
      _selectionMode = false;
    });
    final invoiceFuture = repository.getSalesInvoices(
      context: _context,
      from: _from,
      to: _to,
    );
    final result = await repository.getSalesAnalytics(
      context: _context,
      from: _from,
      to: _to,
    );
    final invoicesResult = await invoiceFuture;
    if (!mounted ||
        epoch != _reportEpoch ||
        requestedStore != widget.membership.storeId ||
        requestedUser != widget.user.id) {
      return;
    }
    if (invoicesResult is Success<SalesInvoiceReport>) {
      _invoices = invoicesResult.value;
    } else if (invoicesResult is FailureResult<SalesInvoiceReport>) {
      _invoiceError = invoicesResult.failure.message;
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
          'sales_analytics_${_formatDate(_from)}_${_formatDate(_to)}';
      if (share) {
        await Printing.sharePdf(bytes: bytes, filename: '$filename.pdf');
      } else {
        await Printing.layoutPdf(onLayout: (_) async => bytes);
      }
    } catch (error) {
      _showMessage('تعذر تجهيز PDF: $error');
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  bool _canReturnInvoice(SalesInvoiceSummary invoice) {
    final role = widget.membership.role;
    final authorized = role.canManageSales || role.canPostAccounting;
    final supportedPayment = const {'cash', 'bank', 'card', 'credit'}
        .contains(invoice.paymentMethod);
    return widget.saleRepository != null &&
        authorized &&
        supportedPayment &&
        !invoice.isFullyReturned &&
        _returningInvoiceId == null &&
        !_isExporting;
  }

  SaleReturnPostingAccounts _returnAccounts(SalesInvoiceSummary invoice) {
    String? settlementAccountId;
    switch (invoice.paymentMethod) {
      case 'cash':
        settlementAccountId = '1110';
      case 'bank':
        settlementAccountId = '1121';
      case 'card':
        settlementAccountId = '1160';
      case 'credit':
        settlementAccountId = null;
    }
    return SaleReturnPostingAccounts(
      settlementAccountId: settlementAccountId,
      customerReceivableAccountId:
          invoice.paymentMethod == 'credit' ? '1140' : null,
      salesReturnsAccountId: '4200',
      inventoryAccountId: '1150',
      costOfSalesAccountId: '5100',
      taxAccountId: invoice.tax.isZero ? null : '2120',
    );
  }

  Future<void> _returnFullInvoice(SalesInvoiceSummary invoice) async {
    final repository = widget.saleRepository;
    if (repository == null || !_canReturnInvoice(invoice)) {
      return;
    }

    final pending = _pendingFullReturns[invoice.id];
    final reasonController = TextEditingController(
      text: pending?.reason ?? 'إرجاع كامل للفاتورة ${invoice.id}',
    );
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(
            pending == null
                ? 'تأكيد إرجاع الفاتورة بالكامل'
                : 'إعادة محاولة الإرجاع الكامل',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                pending == null
                    ? 'سيتم عكس كامل الفاتورة ${invoice.id} محاسبياً '
                        'ومخزنياً. هذه العملية لا تحذف البيع الأصلي.'
                    : 'ستُعاد محاولة نفس عملية الإرجاع السابقة بنفس '
                        'المعرّف والتاريخ والسبب لمنع تكرار القيد.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                enabled: pending == null,
                maxLength: 250,
                decoration: const InputDecoration(
                  labelText: 'سبب الإرجاع',
                  hintText: 'اكتب سبب الإرجاع',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(
                reasonController.text.trim(),
              ),
              icon: const Icon(Icons.undo),
              label: Text(
                pending == null ? 'تأكيد الإرجاع الكامل' : 'إعادة المحاولة',
              ),
            ),
          ],
        ),
      ),
    );
    reasonController.dispose();
    if (!mounted || reason == null) {
      return;
    }

    final returnId = 'full-return-${invoice.id}';
    final saleReturn = pending ??
        SaleReturn(
          id: returnId,
          storeId: widget.membership.storeId,
          idempotencyKey: IdempotencyKey(returnId),
          originalSaleId: invoice.id,
          postedAt: DateTime.now().toUtc(),
          reason: reason.isEmpty ? null : reason,
        );
    _pendingFullReturns[invoice.id] = saleReturn;

    final requestedStore = widget.membership.storeId;
    final requestedUser = widget.user.id;
    setState(() => _returningInvoiceId = invoice.id);
    try {
      final result = await repository.postFullSaleReturn(
        context: _context,
        saleReturn: saleReturn,
        accounts: _returnAccounts(invoice),
      );
      if (!mounted ||
          requestedStore != widget.membership.storeId ||
          requestedUser != widget.user.id) {
        return;
      }
      if (result is FailureResult<SaleReturnPostingResult>) {
        if (result.failure is! InfrastructureFailure) {
          _pendingFullReturns.remove(invoice.id);
        }
        _showMessage('تعذر إرجاع الفاتورة: ${result.failure.message}');
        return;
      }

      final posted = (result as Success<SaleReturnPostingResult>).value;
      _pendingFullReturns.remove(invoice.id);
      _showMessage(
        posted.alreadyReturned
            ? 'الفاتورة كانت مُرجعة بالفعل؛ تم تأكيد نفس عملية الإرجاع.'
            : 'تم إرجاع الفاتورة بالكامل وعكس القيد والمخزون.',
      );
      await _load();
    } catch (error) {
      if (mounted) {
        _showMessage(
          'تعذر التأكد من نتيجة الإرجاع. أعد المحاولة على نفس الفاتورة؛ '
          'سيُعاد استخدام نفس الطلب المحاسبي حرفياً.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _returningInvoiceId = null);
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

  Future<void> _exportXlsx() async {
    final analytics = _analytics;
    if (analytics == null || _isExporting) {
      return;
    }

    setState(() => _isExporting = true);
    try {
      final query = _searchController.text.trim().toLowerCase();
      late final Uint8List bytes;
      late final String filename;
      var truncated = false;

      if (_selectedTab == 0) {
        final report = _invoices;
        if (report == null) {
          _showMessage('تعذر تحميل تفاصيل الفواتير.');
          return;
        }
        final customers = _customerNames();
        final invoices = _matchingInvoices(report, analytics);
        bytes = _salesExcelExport.invoices(
          invoices: invoices,
          customerNames: customers,
        );
        filename = 'sales_details_${_formatDate(_from)}_${_formatDate(_to)}';
        truncated = report.mayBeTruncated;
      } else if (_selectedTab == 1) {
        final products = analytics.productRows
            .where((row) => row.label.toLowerCase().contains(query))
            .toList(growable: false);
        final categories = analytics.categoryRows
            .where((row) => row.label.toLowerCase().contains(query))
            .toList(growable: false);
        bytes = _salesExcelExport.topProducts(
          products: products,
          categories: categories,
        );
        filename =
            'sales_top_products_${_formatDate(_from)}_${_formatDate(_to)}';
        truncated = analytics.mayBeTruncated;
      } else {
        final customers = analytics.customerRows
            .where((row) => row.label.toLowerCase().contains(query))
            .toList(growable: false);
        bytes = _salesExcelExport.customers(
          customers: customers,
          paymentMethodCounts: analytics.paymentMethodCounts,
        );
        filename = 'sales_customers_${_formatDate(_from)}_${_formatDate(_to)}';
        truncated = analytics.mayBeTruncated;
      }

      await FileSaver.instance.saveFile(
        name: filename,
        bytes: bytes,
        fileExtension: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
      if (mounted) {
        _showMessage(
          truncated
              ? 'تم تصدير XLSX للبيانات المحمّلة فقط؛ ضيّق الفترة لاعتماد تقرير كامل.'
              : 'تم تصدير ملف XLSX بنجاح.',
        );
      }
    } catch (error) {
      if (mounted) {
        _showMessage('تعذر تصدير XLSX: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _copyCsv() async {
    final analytics = _analytics;
    if (analytics == null) {
      return;
    }

    final query = _searchController.text.trim().toLowerCase();
    if (_selectedTab == 0) {
      final report = _invoices;
      if (report == null) {
        _showMessage('تعذر تحميل تفاصيل الفواتير.');
        return;
      }
      final customers = {
        for (final row in analytics.customerRows) row.key: row.label,
      };
      final rows = <String>[
        'invoice_id,posted_at_utc,customer,payment,subtotal_minor_units,'
            'tax_minor_units,total_minor_units,cost_minor_units,currency,'
            'journal_entry_id',
        for (final item in report.invoices)
          if (query.isEmpty ||
              item.id.toLowerCase().contains(query) ||
              (customers[item.customerId] ?? item.customerId ?? 'بدون عميل')
                  .toLowerCase()
                  .contains(query) ||
              (item.description?.toLowerCase().contains(query) ?? false))
            [
              _csvValue(item.id),
              _csvValue(item.postedAt.toUtc().toIso8601String()),
              _csvValue(
                  customers[item.customerId] ?? item.customerId ?? 'بدون عميل'),
              _csvValue(item.paymentMethod),
              item.subtotal.minorUnits.toString(),
              item.tax.minorUnits.toString(),
              item.total.minorUnits.toString(),
              item.cost.minorUnits.toString(),
              _csvValue(item.total.currency),
              _csvValue(item.journalEntryId),
            ].join(','),
      ];
      await Clipboard.setData(ClipboardData(text: rows.join('\r\n')));
      if (mounted) {
        _showMessage(report.mayBeTruncated
            ? 'تم نسخ الفواتير المحمّلة فقط، وبعض الفواتير خارج سقف التحميل.'
            : 'تم نسخ تفاصيل الفواتير المحمّلة بصيغة CSV.');
      }
      return;
    }

    final rows = <String>[
      'group,name,quantity,sales,cost,gross_profit,currency',
      for (final row in [
        if (_selectedTab == 1)
          ...analytics.productRows.map((value) => ('product', value)),
        if (_selectedTab == 1)
          ...analytics.categoryRows.map((value) => ('category', value)),
        if (_selectedTab == 2)
          ...analytics.customerRows.map((value) => ('customer', value)),
      ])
        if (row.$2.label.toLowerCase().contains(query))
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
    // Prevent spreadsheet formula execution after CSV is pasted into Excel.
    final dangerous =
        value.isNotEmpty && '=+-@\\t\\r'.contains(value.substring(0, 1));
    final safe = dangerous ? "'$value" : value;
    return '"${safe.replaceAll('"', '""')}"';
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
