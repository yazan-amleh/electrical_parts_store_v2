import 'package:flutter/material.dart';

import '../../../core/money/money.dart';
import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../domain/entities/financial_statements.dart';
import '../domain/entities/trial_balance.dart';
import '../domain/repositories/accounting_query_repository.dart';

enum _StatementView { trialBalance, incomeStatement, balanceSheet }

class FinancialStatementsPage extends StatefulWidget {
  const FinancialStatementsPage({
    required this.repository,
    required this.user,
    required this.membership,
    super.key,
  });

  final AccountingQueryRepository? repository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<FinancialStatementsPage> createState() =>
      _FinancialStatementsPageState();
}

class _FinancialStatementsPageState extends State<FinancialStatementsPage> {
  TrialBalance? _trialBalance;
  _StatementView _selectedView = _StatementView.trialBalance;
  bool _isLoading = true;
  String? _errorMessage;

  FinancialStatements? get _statements {
    final trialBalance = _trialBalance;
    return trialBalance == null
        ? null
        : FinancialStatements.fromTrialBalance(trialBalance);
  }

  @override
  void initState() {
    super.initState();
    _loadTrialBalance();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final repository = widget.repository;
    if (repository == null) {
      return const Center(
        child: Text('مستودع التقارير المحاسبية غير موصول بهذه البيئة.'),
      );
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return _buildErrorState();
    }

    final trialBalance = _trialBalance;
    final statements = _statements;
    if (trialBalance == null || statements == null) {
      return const Center(child: Text('لا توجد بيانات مالية.'));
    }

    return RefreshIndicator(
      onRefresh: _loadTrialBalance,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, trialBalance, statements),
            const SizedBox(height: 12),
            switch (_selectedView) {
              _StatementView.trialBalance => _buildTrialBalance(trialBalance),
              _StatementView.incomeStatement => _buildIncomeStatement(
                  statements,
                ),
              _StatementView.balanceSheet => _buildBalanceSheet(statements),
            },
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    TrialBalance trialBalance,
    FinancialStatements statements,
  ) {
    final balanceSheetIsBalanced = statements.balanceSheetDifference.isZero;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.assessment_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'القوائم والميزان',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'تحديث',
                  onPressed: _loadTrialBalance,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('ميزان المراجعة'),
                  selected: _selectedView == _StatementView.trialBalance,
                  onSelected: (_) => setState(
                    () => _selectedView = _StatementView.trialBalance,
                  ),
                ),
                ChoiceChip(
                  label: const Text('قائمة الدخل'),
                  selected: _selectedView == _StatementView.incomeStatement,
                  onSelected: (_) => setState(
                    () => _selectedView = _StatementView.incomeStatement,
                  ),
                ),
                ChoiceChip(
                  label: const Text('المركز المالي'),
                  selected: _selectedView == _StatementView.balanceSheet,
                  onSelected: (_) => setState(
                    () => _selectedView = _StatementView.balanceSheet,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  trialBalance.isBalanced && balanceSheetIsBalanced
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_outlined,
                  color: trialBalance.isBalanced && balanceSheetIsBalanced
                      ? Colors.green
                      : Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    trialBalance.isBalanced && balanceSheetIsBalanced
                        ? 'الميزان والمركز المالي متوازنان.'
                        : 'يوجد فرق يحتاج إلى مراجعة قبل الاعتماد.',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrialBalance(TrialBalance trialBalance) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'ميزان المراجعة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('الحساب')),
                  DataColumn(label: Text('مدين')),
                  DataColumn(label: Text('دائن')),
                  DataColumn(label: Text('الرصيد الطبيعي')),
                ],
                rows: [
                  for (final line in trialBalance.lines)
                    DataRow(
                      cells: [
                        DataCell(
                          Text('${line.account.code} — ${line.account.name}'),
                        ),
                        DataCell(Text(line.debit.formatted)),
                        DataCell(Text(line.credit.formatted)),
                        DataCell(
                          Text(
                            line.account.normalSide.name == 'debit'
                                ? (line.debit - line.credit).formatted
                                : (line.credit - line.debit).formatted,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const Divider(),
            _totalRow(
              label: 'الإجمالي',
              value:
                  '${trialBalance.totalDebit.formatted} / ${trialBalance.totalCredit.formatted}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomeStatement(FinancialStatements statements) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStatementSection(
          title: 'الإيرادات',
          icon: Icons.trending_up_outlined,
          lines: statements.revenue,
          total: statements.totalRevenue,
        ),
        _buildStatementSection(
          title: 'تكلفة المبيعات',
          icon: Icons.inventory_2_outlined,
          lines: statements.costOfSales,
          total: statements.totalCostOfSales,
        ),
        _buildSummaryCard('مجمل الربح', statements.grossProfit),
        _buildStatementSection(
          title: 'المصروفات التشغيلية',
          icon: Icons.receipt_long_outlined,
          lines: statements.operatingExpenses,
          total: statements.totalOperatingExpenses,
        ),
        _buildStatementSection(
          title: 'إيرادات أخرى',
          icon: Icons.add_chart_outlined,
          lines: statements.otherIncome,
          total: statements.totalOtherIncome,
        ),
        _buildStatementSection(
          title: 'مصروفات أخرى',
          icon: Icons.trending_down_outlined,
          lines: statements.otherExpenses,
          total: statements.totalOtherExpenses,
        ),
        _buildSummaryCard('صافي الربح / الخسارة', statements.netIncome),
      ],
    );
  }

  Widget _buildBalanceSheet(FinancialStatements statements) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStatementSection(
          title: 'الأصول المتداولة',
          icon: Icons.account_balance_wallet_outlined,
          lines: statements.currentAssets,
          total: statements.totalCurrentAssets,
        ),
        _buildStatementSection(
          title: 'الأصول غير المتداولة',
          icon: Icons.business_outlined,
          lines: statements.nonCurrentAssets,
          total: statements.totalNonCurrentAssets,
        ),
        _buildSummaryCard('إجمالي الأصول', statements.totalAssets),
        _buildStatementSection(
          title: 'الالتزامات المتداولة',
          icon: Icons.receipt_long_outlined,
          lines: statements.currentLiabilities,
          total: statements.totalCurrentLiabilities,
        ),
        _buildStatementSection(
          title: 'الالتزامات غير المتداولة',
          icon: Icons.account_balance_outlined,
          lines: statements.nonCurrentLiabilities,
          total: statements.totalNonCurrentLiabilities,
        ),
        _buildStatementSection(
          title: 'حقوق الملكية',
          icon: Icons.groups_outlined,
          lines: statements.equity,
          total: statements.totalEquity,
        ),
        _buildSummaryCard('صافي الربح للفترة', statements.netIncome),
        _buildSummaryCard(
          'إجمالي الالتزامات وحقوق الملكية',
          statements.totalLiabilitiesAndEquity,
        ),
        _buildSummaryCard(
          'فرق التوازن',
          statements.balanceSheetDifference,
          highlight: statements.balanceSheetDifference.isZero,
        ),
      ],
    );
  }

  Widget _buildStatementSection({
    required String title,
    required IconData icon,
    required List<FinancialStatementLine> lines,
    required Money total,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(total.formatted),
              ],
            ),
            if (lines.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12, bottom: 8),
                child: Text('لا توجد أرصدة ضمن هذا القسم.'),
              )
            else
              for (final line in lines)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${line.account.code} — ${line.account.name}'),
                  trailing: Text(line.amount.formatted),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(
    String label,
    Money value, {
    bool highlight = false,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: highlight ? Colors.green.withValues(alpha: 0.12) : null,
      child: ListTile(
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: Text(
          value.formatted,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _totalRow({required String label, required String value}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          Text(_errorMessage!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loadTrialBalance,
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadTrialBalance() async {
    final repository = widget.repository;
    if (repository == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final result = await repository.getTrialBalance(
      context: StoreContext(
        storeId: widget.membership.storeId,
        userId: widget.user.id,
      ),
    );
    if (!mounted) {
      return;
    }

    if (result is FailureResult<TrialBalance>) {
      setState(() {
        _isLoading = false;
        _errorMessage = result.failure.message;
      });
      return;
    }
    if (result is Success<TrialBalance>) {
      setState(() {
        _isLoading = false;
        _trialBalance = result.value;
      });
    }
  }
}
