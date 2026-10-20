import 'package:flutter/material.dart';

import '../../../core/money/money.dart';
import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../domain/entities/accounting_audit_report.dart';
import '../domain/repositories/accounting_audit_repository.dart';

class AccountingAuditPage extends StatefulWidget {
  const AccountingAuditPage({
    required this.repository,
    required this.user,
    required this.membership,
    super.key,
  });

  final AccountingAuditRepository? repository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<AccountingAuditPage> createState() => _AccountingAuditPageState();
}

class _AccountingAuditPageState extends State<AccountingAuditPage> {
  bool _isLoading = true;
  String? _errorMessage;
  AccountingAuditReport? _report;

  @override
  void initState() {
    super.initState();
    _runAudit();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (widget.repository == null) {
      return const Center(
        child: Text('مستودع تدقيق المحاسبة غير موصول بهذه البيئة.'),
      );
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return _buildErrorState(context);
    }

    final report = _report;
    if (report == null) {
      return const Center(child: Text('لم يتم إنشاء تقرير التدقيق.'));
    }

    return RefreshIndicator(
      onRefresh: _runAudit,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSummary(context, report),
            const SizedBox(height: 12),
            _buildCheckedMetrics(report),
            const SizedBox(height: 12),
            _buildIssues(context, report),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(
    BuildContext context,
    AccountingAuditReport report,
  ) {
    final color = report.isHealthy ? Colors.green : Colors.red;
    final icon = report.isHealthy
        ? Icons.check_circle_outline
        : Icons.error_outline;
    final title = report.isHealthy
        ? report.warningCount == 0
            ? 'المحاسبة متطابقة'
            : 'المحاسبة متطابقة مع تنبيهات'
        : 'يوجد فرق محاسبي يحتاج إلى معالجة';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'آخر فحص: ${_formatDate(report.generatedAt)}',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'الأخطاء: ${report.errorCount} — التنبيهات: ${report.warningCount}',
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'إعادة الفحص',
              onPressed: _runAudit,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckedMetrics(AccountingAuditReport report) {
    final metrics = <String, int>{
      'الحسابات': report.accountsChecked,
      'القيود': report.journalEntriesChecked,
      'سطور القيود': report.journalLinesChecked,
      'الأطراف': report.partiesChecked,
      'حركات الأطراف': report.partyLedgerEntriesChecked,
      'الأصناف': report.productsChecked,
      'حركات المخزون': report.inventoryMovementsChecked,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final entry in metrics.entries)
              Chip(
                avatar: const Icon(Icons.fact_check_outlined, size: 18),
                label: Text('${entry.key}: ${entry.value}'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIssues(
    BuildContext context,
    AccountingAuditReport report,
  ) {
    if (report.issues.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.verified_outlined, color: Colors.green, size: 42),
              SizedBox(height: 8),
              Text(
                'لم يتم العثور على فرق بين مصدر الحركة والإسقاطات.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: ExpansionPanelList.radio(
          children: [
            for (var index = 0; index < report.issues.length; index++)
              ExpansionPanelRadio(
                value: index,
                headerBuilder: (context, isExpanded) {
                  final issue = report.issues[index];
                  return ListTile(
                    leading: Icon(
                      issue.isError
                          ? Icons.error_outline
                          : Icons.warning_amber_outlined,
                      color: issue.isError ? Colors.red : Colors.orange,
                    ),
                    title: Text(issue.message),
                    subtitle: Text(
                      '${issue.scope} — ${issue.referenceId}',
                    ),
                  );
                },
                body: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    56,
                    0,
                    16,
                    16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('رمز الفحص: ${report.issues[index].code}'),
                      if (report.issues[index].expected != null ||
                          report.issues[index].actual != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'المتوقع: ${_formatValue(report.issues[index], report.issues[index].expected)}',
                        ),
                        Text(
                          'المخزن: ${_formatValue(report.issues[index], report.issues[index].actual)}',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'تعذر تشغيل فحص المحاسبة.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _runAudit,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runAudit() async {
    final repository = widget.repository;
    if (repository == null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await repository.runAudit(
      context: StoreContext(
        storeId: widget.membership.storeId,
        userId: widget.user.id,
      ),
    );

    if (!mounted) {
      return;
    }

    if (result is Success<AccountingAuditReport>) {
      setState(() {
        _report = result.value;
        _isLoading = false;
      });
    } else if (result is FailureResult<AccountingAuditReport>) {
      setState(() {
        _errorMessage = result.failure.message;
        _isLoading = false;
      });
    }
  }

  String _formatValue(AccountingAuditIssue issue, int? value) {
    if (value == null) {
      return '—';
    }
    if (issue.valueKind == 'minorUnits') {
      return Money(
        minorUnits: value,
        currency: issue.currency ?? 'ILS',
      ).formatted;
    }
    if (issue.valueKind == 'milliUnits') {
      final sign = value < 0 ? '-' : '';
      return '\$sign${(value.abs() / 1000).toStringAsFixed(3)}';
    }
    return value.toString();
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
