import 'package:flutter/material.dart';

import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../domain/entities/trial_balance.dart';
import '../domain/repositories/accounting_query_repository.dart';

class TrialBalancePage extends StatefulWidget {
  const TrialBalancePage({
    required this.repository,
    required this.user,
    required this.membership,
    super.key,
  });

  final AccountingQueryRepository? repository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<TrialBalancePage> createState() => _TrialBalancePageState();
}

class _TrialBalancePageState extends State<TrialBalancePage> {
  TrialBalance? _trialBalance;
  bool _isLoading = true;
  String? _errorMessage;

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

    final trialBalance = _trialBalance;
    if (trialBalance == null) {
      return const Center(child: Text('لا توجد بيانات ميزان مراجعة.'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.balance_outlined),
                  const SizedBox(width: 8),
                  Text(
                    'ميزان المراجعة',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  Icon(
                    trialBalance.isBalanced
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_outlined,
                    color: trialBalance.isBalanced
                        ? Colors.green
                        : Theme.of(context).colorScheme.error,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('الحساب')),
                    DataColumn(label: Text('مدين')),
                    DataColumn(label: Text('دائن')),
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
                        ],
                      ),
                  ],
                ),
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'الإجمالي',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(trialBalance.totalDebit.formatted),
                  Text(trialBalance.totalCredit.formatted),
                ],
              ),
            ],
          ),
        ),
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
