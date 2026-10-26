import 'package:flutter/material.dart';

import '../../../core/money/money.dart';
import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../../accounting/domain/entities/account.dart';
import '../../accounting/domain/entities/trial_balance.dart';
import '../../accounting/domain/enums/accounting_enums.dart';
import '../../accounting/domain/repositories/accounting_query_repository.dart';
import '../../inventory/domain/entities/product.dart';
import '../../inventory/domain/repositories/product_repository.dart';
import '../../reports/domain/repositories/reports_repository.dart';
import '../../reports/domain/entities/operational_report.dart';
import 'dashboard_quick_access.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    required this.accountingQueryRepository,
    required this.productRepository,
    this.reportsRepository,
    this.onOpenModule,
    required this.user,
    required this.membership,
    super.key,
  });

  final AccountingQueryRepository? accountingQueryRepository;
  final ProductRepository? productRepository;
  final ReportsRepository? reportsRepository;
  final ValueChanged<String>? onOpenModule;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String _selectedCurrency = 'ILS';
  String get _currency => _selectedCurrency;

  TrialBalance? _trialBalance;
  List<Product> _products = const <Product>[];
  OperationalReport? _operationalReport;
  String? _operationalError;
  bool _isLoading = true;
  String? _errorMessage;

  StoreContext get _storeContext {
    return StoreContext(
      storeId: widget.membership.storeId,
      userId: widget.user.id,
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.accountingQueryRepository == null ||
        widget.productRepository == null) {
      return _buildNavigationHome(
        const Text('مستودعات لوحة التحكم غير موصولة بهذه البيئة.'),
      );
    }
    if (_isLoading) {
      return _buildNavigationHome(
        const CircularProgressIndicator(),
      );
    }
    if (_errorMessage != null || _trialBalance == null) {
      return _buildNavigationHome(_buildErrorState());
    }

    final metrics = _buildMetrics();
    final lowStockProducts =
        _products.where((product) => product.isLowStock).toList()
          ..sort(
            (left, right) => left.quantityOnHand.milliUnits.compareTo(
              right.quantityOnHand.milliUnits,
            ),
          );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            _buildHeader(context),
            if (widget.onOpenModule != null) ...[
              const SizedBox(height: 18),
              DashboardQuickAccess(
                storeId: widget.membership.storeId,
                userId: widget.user.id,
                role: widget.membership.role,
                onOpenModule: widget.onOpenModule!,
              ),
            ],
            const SizedBox(height: 12),
            _buildCurrencySelector(),
            const SizedBox(height: 12),
            _buildOperationalSummary(context),
            const SizedBox(height: 20),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: metrics.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 250,
                mainAxisExtent: 132,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemBuilder: (context, index) {
                return _buildMetricCard(context, metrics[index]);
              },
            ),
            const SizedBox(height: 20),
            _buildIntegrityCard(context),
            const SizedBox(height: 12),
            _buildLowStockCard(context, lowStockProducts),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationHome(Widget status) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildHeader(context),
          if (widget.onOpenModule != null) ...[
            const SizedBox(height: 18),
            DashboardQuickAccess(
              storeId: widget.membership.storeId,
              userId: widget.user.id,
              role: widget.membership.role,
              onOpenModule: widget.onOpenModule!,
            ),
          ],
          const SizedBox(height: 24),
          Center(child: status),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final displayName = widget.user.displayName?.trim();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 26,
              child: Icon(Icons.dashboard_outlined),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'أهلاً بك، ${displayName?.isNotEmpty == true ? displayName : widget.user.email}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'المتجر: ${widget.membership.storeId} • المبالغ حسب العملة المختارة من الإسقاطات المحاسبية',
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'تحديث',
              onPressed: _isLoading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrencySelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final currency in const ['ILS', 'USD', 'JOD'])
          ChoiceChip(
            label: Text(currency),
            selected: _selectedCurrency == currency,
            onSelected: (_) => setState(() => _selectedCurrency = currency),
          ),
      ],
    );
  }

  Widget _buildOperationalSummary(BuildContext context) {
    final report = _operationalReport;
    if (widget.reportsRepository == null) {
      return const SizedBox.shrink();
    }
    if (_operationalError != null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('ملخص العمليات لهذا الشهر غير متاح'),
          subtitle: Text(_operationalError!),
        ),
      );
    }
    if (report == null) return const SizedBox.shrink();
    if (report.mayBeTruncated) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.warning_amber_outlined),
          title: Text('البيانات التشغيلية غير مكتملة'),
          subtitle: Text('تجاوز التقرير حد القراءة؛ لا تعرض أرقامًا جزئية.'),
        ),
      );
    }
    if (report.salesRevenue.currency != _currency) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text('ملخص العمليات — $_currency'),
          subtitle: const Text(
            'مصدر التقرير الحالي لا يدعم فصل العملات تلقائيًا؛ '
            'لن تعرض أرقام بعملة أخرى.',
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            Text('عمليات الشهر — $_currency'),
            Text('المبيعات: ${report.salesRevenue.formatted} '
                '(${report.salesCount} فاتورة)'),
            Text('المشتريات: ${report.purchasesTotal.formatted} '
                '(${report.purchasesCount} فاتورة)'),
            Text('المصروفات: ${report.expensesTotal.formatted}'),
          ],
        ),
      ),
    );
  }

  List<_DashboardMetric> _buildMetrics() {
    return [
      _DashboardMetric(
        title: 'السيولة',
        subtitle: 'الصندوق والبنوك',
        value: _sumWhere(
          (account) =>
              account.controlType == ControlType.cashBox ||
              account.controlType == ControlType.bank,
        ),
        icon: Icons.account_balance_wallet_outlined,
      ),
      _DashboardMetric(
        title: 'ذمم العملاء',
        subtitle: 'الرصيد المدين',
        value: _sumWhere(
          (account) => account.controlType == ControlType.customerReceivable,
        ),
        icon: Icons.people_outline,
      ),
      _DashboardMetric(
        title: 'المخزون',
        subtitle: 'قيمة المخزون',
        value: _sumWhere(
          (account) => account.controlType == ControlType.inventory,
        ),
        icon: Icons.inventory_2_outlined,
      ),
      _DashboardMetric(
        title: 'المبيعات',
        subtitle: 'تراكمي من القيود',
        value: _sumWhere((account) => account.type == AccountType.revenue),
        icon: Icons.point_of_sale_outlined,
      ),
      _DashboardMetric(
        title: 'المصاريف',
        subtitle: 'تراكمي من القيود',
        value: _sumWhere((account) => account.type == AccountType.expense),
        icon: Icons.receipt_long_outlined,
      ),
      _DashboardMetric(
        title: 'الأصناف الفعالة',
        subtitle: 'عدد الأصناف المتاحة',
        value: Money(
          minorUnits: _products.where((product) => product.isActive).length,
          currency: _currency,
        ),
        icon: Icons.inventory_2_outlined,
        displayAsCount: true,
      ),
      _DashboardMetric(
        title: 'أصناف منخفضة',
        subtitle: 'تحت حد إعادة الطلب',
        value: Money(
          minorUnits: _products.where((product) => product.isLowStock).length,
          currency: _currency,
        ),
        icon: Icons.warning_amber_outlined,
        displayAsCount: true,
      ),
    ];
  }

  Widget _buildMetricCard(BuildContext context, _DashboardMetric metric) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: colorScheme.primaryContainer,
              foregroundColor: colorScheme.onPrimaryContainer,
              child: Icon(metric.icon),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    metric.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    metric.displayAsCount
                        ? metric.value.minorUnits.toString()
                        : metric.value.formatted,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    metric.subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntegrityCard(BuildContext context) {
    final lines = _trialBalance!.lines.where(
      (line) => line.account.currency == _currency,
    );
    var debit = Money.zero(currency: _currency);
    var credit = Money.zero(currency: _currency);
    for (final line in lines) {
      debit += line.debit;
      credit += line.credit;
    }
    final isBalanced = debit == credit;
    final color =
        isBalanced ? Colors.green : Theme.of(context).colorScheme.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  isBalanced
                      ? Icons.verified_outlined
                      : Icons.warning_amber_outlined,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isBalanced
                        ? 'ميزان المراجعة متوازن — $_currency'
                        : 'تنبيه: ميزان المراجعة غير متوازن — $_currency',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'إجمالي المدين: ${debit.formatted} • '
              'إجمالي الدائن: ${credit.formatted}',
            ),
            const SizedBox(height: 4),
            Text(
              'مؤشر عرض سريع من الأرصدة الحالية؛ لا يغني عن المطابقة المحاسبية.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLowStockCard(BuildContext context, List<Product> products) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active_outlined),
                const SizedBox(width: 8),
                Text(
                  'تنبيهات المخزون',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (products.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('لا توجد أصناف تحت حد إعادة الطلب.'),
              )
            else
              for (final product in products.take(8))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(product.name),
                  subtitle: Text(
                    'المتاح: ${product.quantityOnHand.formatted} • '
                    'الحد: ${product.minimumQuantity.formatted}',
                  ),
                  trailing: const Icon(Icons.chevron_left),
                ),
            if (products.length > 8)
              Text(
                'وأصناف أخرى عددها ${products.length - 8}.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  Money _sumWhere(bool Function(Account account) predicate) {
    var total = Money.zero(currency: _currency);
    for (final line in _trialBalance!.lines) {
      if (!predicate(line.account)) {
        continue;
      }
      final raw = line.debit - line.credit;
      final normalized = line.account.normalSide == NormalSide.debit
          ? raw
          : Money(minorUnits: -raw.minorUnits, currency: raw.currency);
      if (normalized.currency == _currency) {
        total += normalized;
      }
    }
    return total;
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          Text(
            _errorMessage ?? 'تعذر تحميل لوحة التحكم.',
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
    final accountingRepository = widget.accountingQueryRepository;
    final productRepository = widget.productRepository;
    if (accountingRepository == null || productRepository == null) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _operationalReport = null;
      _operationalError = null;
    });

    final trialBalanceResult = await accountingRepository.getTrialBalance(
      context: _storeContext,
    );
    if (!mounted) {
      return;
    }
    if (trialBalanceResult is FailureResult<TrialBalance>) {
      setState(() {
        _isLoading = false;
        _errorMessage = trialBalanceResult.failure.message;
      });
      return;
    }

    final productResult = await productRepository.getProducts(
      context: _storeContext,
    );
    if (!mounted) {
      return;
    }
    if (productResult is FailureResult<List<Product>>) {
      setState(() {
        _isLoading = false;
        _errorMessage = productResult.failure.message;
      });
      return;
    }

    OperationalReport? operational;
    String? operationalError;
    final reportsRepository = widget.reportsRepository;
    if (reportsRepository != null) {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month);
      final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
      final result = await reportsRepository.getOperationalReport(
        context: _storeContext,
        from: start,
        to: end,
      );
      if (!mounted) return;
      if (result is Success<OperationalReport>) {
        operational = result.value;
      } else if (result is FailureResult<OperationalReport>) {
        operationalError = result.failure.message;
      }
    }

    if (trialBalanceResult is Success<TrialBalance> &&
        productResult is Success<List<Product>>) {
      setState(() {
        _isLoading = false;
        _trialBalance = trialBalanceResult.value;
        _products = productResult.value;
        _operationalReport = operational;
        _operationalError = operationalError;
      });
    }
  }
}

class _DashboardMetric {
  const _DashboardMetric({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.icon,
    this.displayAsCount = false,
  });

  final String title;
  final String subtitle;
  final Money value;
  final IconData icon;
  final bool displayAsCount;
}
