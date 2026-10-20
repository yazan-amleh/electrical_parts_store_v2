import 'package:flutter/material.dart';

import '../../../core/money/money.dart';
import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../../inventory/domain/entities/product.dart';
import '../../inventory/domain/repositories/product_repository.dart';
import '../domain/entities/operational_report.dart';
import '../domain/repositories/reports_repository.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({
    required this.repository,
    required this.productRepository,
    required this.user,
    required this.membership,
    super.key,
  });

  final ReportsRepository? repository;
  final ProductRepository? productRepository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late DateTime _from;
  late DateTime _to;
  OperationalReport? _report;
  List<Product> _products = const <Product>[];
  bool _isLoading = true;
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
        child: Text('مستودع التقارير غير موصول بهذه البيئة.'),
      );
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null || _report == null) {
      return _buildErrorState();
    }

    final report = _report!;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _buildHeader(context),
            const SizedBox(height: 12),
            _buildMetrics(context, report),
            const SizedBox(height: 12),
            _buildPaymentBreakdown(context, report),
            const SizedBox(height: 12),
            _buildInventorySummary(context, report),
            const SizedBox(height: 12),
            _buildTransactions(context, report),
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
                const Icon(Icons.analytics_outlined, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'التقارير والتصدير',
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
              'تقرير تشغيلي مبني على مستندات V2 المرحّلة. القوائم الرسمية '
              'والميزان متاحة من وحدة المحاسبة.',
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

  Widget _buildMetrics(BuildContext context, OperationalReport report) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _metricCard(
          context,
          title: 'المبيعات',
          value: report.salesRevenue,
          subtitle: '${report.salesCount} فاتورة',
          icon: Icons.point_of_sale_outlined,
        ),
        _metricCard(
          context,
          title: 'تكلفة المبيعات',
          value: report.salesCost,
          subtitle: 'من تكلفة الأصناف المرحّلة',
          icon: Icons.inventory_2_outlined,
        ),
        _metricCard(
          context,
          title: 'مجمل الربح',
          value: report.grossProfit,
          subtitle: 'المبيعات ناقص التكلفة',
          icon: Icons.trending_up_outlined,
        ),
        _metricCard(
          context,
          title: 'المصروفات',
          value: report.expensesTotal,
          subtitle: '${report.expensesCount} مصروف',
          icon: Icons.receipt_long_outlined,
        ),
        _metricCard(
          context,
          title: 'نتيجة التشغيل',
          value: report.operatingResult,
          subtitle: 'قبل البنود الأخرى',
          icon: Icons.assessment_outlined,
        ),
        _metricCard(
          context,
          title: 'المشتريات',
          value: report.purchasesTotal,
          subtitle: '${report.purchasesCount} فاتورة',
          icon: Icons.shopping_cart_outlined,
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
      width: 250,
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

  Widget _buildPaymentBreakdown(
    BuildContext context,
    OperationalReport report,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'توزيع طرق الدفع',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (report.salesByPaymentMethod.isEmpty)
              const Text('لا توجد مبيعات ضمن الفترة.')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in report.salesByPaymentMethod.entries)
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

  Widget _buildInventorySummary(
    BuildContext context,
    OperationalReport report,
  ) {
    final currency = report.salesRevenue.currency;
    var inventoryValue = Money.zero(currency: currency);
    var lowStock = 0;
    for (final product in _products) {
      if (product.inventoryValue.currency == currency) {
        inventoryValue += product.inventoryValue;
      }
      if (product.isLowStock) {
        lowStock++;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 18,
          runSpacing: 12,
          children: [
            _inventoryTile(
              context,
              title: 'الأصناف الفعالة',
              value: _products
                  .where((product) => product.isActive)
                  .length
                  .toString(),
              icon: Icons.inventory_2_outlined,
            ),
            _inventoryTile(
              context,
              title: 'قيمة المخزون',
              value: inventoryValue.formatted,
              icon: Icons.warehouse_outlined,
            ),
            _inventoryTile(
              context,
              title: 'تحت حد الطلب',
              value: lowStock.toString(),
              icon: Icons.warning_amber_outlined,
            ),
          ],
        ),
      ),
    );
  }

  Widget _inventoryTile(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
  }) {
    return SizedBox(
      width: 220,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(
          value,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }

  Widget _buildTransactions(
    BuildContext context,
    OperationalReport report,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'آخر الحركات ضمن الفترة',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (report.transactions.isEmpty)
              const Text('لا توجد حركات مرحّلة ضمن الفترة.')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('التاريخ')),
                    DataColumn(label: Text('النوع')),
                    DataColumn(label: Text('الوصف')),
                    DataColumn(label: Text('طريقة الدفع')),
                    DataColumn(label: Text('المبلغ')),
                  ],
                  rows: [
                    for (final transaction in report.transactions.take(100))
                      DataRow(
                        cells: [
                          DataCell(Text(_formatDate(transaction.postedAt))),
                          DataCell(Text(_sourceLabel(transaction.source))),
                          DataCell(
                            Text(
                              transaction.description ??
                                  'مستند ${transaction.id}',
                            ),
                          ),
                          DataCell(
                            Text(
                              transaction.paymentMethod == null
                                  ? '—'
                                  : _paymentLabel(
                                      transaction.paymentMethod!,
                                    ),
                            ),
                          ),
                          DataCell(Text(transaction.amount.formatted)),
                        ],
                      ),
                  ],
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
            _errorMessage ?? 'تعذر تحميل التقرير.',
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
      setState(() {
        _errorMessage = 'بداية الفترة يجب أن تسبق نهايتها.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final reportResult = await repository.getOperationalReport(
      context: _context,
      from: _from,
      to: _to,
    );
    if (!mounted) {
      return;
    }
    if (reportResult is FailureResult<OperationalReport>) {
      setState(() {
        _isLoading = false;
        _errorMessage = reportResult.failure.message;
      });
      return;
    }

    final productsResult = widget.productRepository == null
        ? null
        : await widget.productRepository!.getProducts(context: _context);
    if (!mounted) {
      return;
    }

    setState(() {
      _report = (reportResult as Success<OperationalReport>).value;
      if (productsResult is Success<List<Product>>) {
        _products = productsResult.value;
      } else if (widget.productRepository == null) {
        _products = const <Product>[];
      }
      _isLoading = false;
    });
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
        _to = DateTime(
          selected.year,
          selected.month,
          selected.day,
          23,
          59,
          59,
        );
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
      _to = DateTime(
        selected.year,
        selected.month,
        selected.day,
        23,
        59,
        59,
      );
    });
  }

  String _formatDate(DateTime date) {
    final utc = date.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'sale':
        return 'مبيعات';
      case 'purchase':
        return 'مشتريات';
      case 'expense':
        return 'مصروف';
      default:
        return source;
    }
  }

  String _paymentLabel(String paymentMethod) {
    switch (paymentMethod) {
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
        return paymentMethod;
    }
  }
}
