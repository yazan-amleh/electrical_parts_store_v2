import 'package:flutter/material.dart';

import '../../../core/money/money.dart';
import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../domain/entities/account.dart';
import '../domain/entities/account_ledger_line.dart';
import '../domain/enums/accounting_enums.dart';
import '../domain/repositories/accounting_query_repository.dart';

class LedgerPage extends StatefulWidget {
  const LedgerPage({
    required this.repository,
    required this.user,
    required this.membership,
    super.key,
  });

  final AccountingQueryRepository? repository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage> {
  List<Account> _accounts = const <Account>[];
  List<AccountLedgerLine> _lines = const <AccountLedgerLine>[];
  String? _selectedAccountId;
  bool _isLoadingAccounts = true;
  bool _isLoadingLedger = false;
  String? _errorMessage;

  Account? get _selectedAccount {
    final accountId = _selectedAccountId;
    if (accountId == null) {
      return null;
    }
    for (final account in _accounts) {
      if (account.id == accountId) {
        return account;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    if (repository == null) {
      return const Center(
        child: Text('مستودع دفتر الأستاذ غير موصول بهذه البيئة.'),
      );
    }
    if (_isLoadingAccounts) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return _buildErrorState();
    }

    final account = _selectedAccount;
    if (account == null) {
      return const Center(child: Text('لا توجد حسابات قابلة للترحيل.'));
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          _buildHeader(account),
          Expanded(child: _buildLedger(account)),
        ],
      ),
    );
  }

  Widget _buildHeader(Account account) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          runSpacing: 12,
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Icon(Icons.book_outlined),
            Text(
              'دفتر الأستاذ',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(
              width: 320,
              child: DropdownButtonFormField<String>(
                initialValue: _selectedAccountId,
                decoration: const InputDecoration(
                  labelText: 'الحساب',
                  prefixIcon: Icon(Icons.account_tree_outlined),
                ),
                items: _accounts
                    .map(
                      (candidate) => DropdownMenuItem<String>(
                        value: candidate.id,
                        child: Text(
                          '${candidate.code} — ${candidate.name}',
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _isLoadingLedger
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() {
                            _selectedAccountId = value;
                            _lines = const <AccountLedgerLine>[];
                          });
                          _loadLedger(value);
                        }
                      },
              ),
            ),
            OutlinedButton.icon(
              onPressed:
                  _isLoadingLedger ? null : () => _loadLedger(account.id),
              icon: const Icon(Icons.refresh),
              label: const Text('تحديث'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLedger(Account account) {
    if (_isLoadingLedger) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_lines.isEmpty) {
      return const Center(child: Text('لا توجد حركات مرحّلة لهذا الحساب.'));
    }

    var running = Money.zero(currency: account.currency);
    final rows = <DataRow>[];
    for (final line in _lines) {
      running = running + line.debit - line.credit;
      final displayBalance = Money(
        minorUnits: account.normalSide == NormalSide.debit
            ? running.minorUnits
            : -running.minorUnits,
        currency: running.currency,
      );
      rows.add(
        DataRow(
          cells: [
            DataCell(Text(_formatDate(line.postedAt))),
            DataCell(
              Text(
                line.description?.trim().isNotEmpty == true
                    ? line.description!
                    : line.entryId,
              ),
            ),
            DataCell(Text(line.debit.formatted)),
            DataCell(Text(line.credit.formatted)),
            DataCell(Text(displayBalance.formatted)),
          ],
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('التاريخ')),
              DataColumn(label: Text('البيان')),
              DataColumn(label: Text('مدين')),
              DataColumn(label: Text('دائن')),
              DataColumn(label: Text('الرصيد')),
            ],
            rows: rows,
          ),
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
          Text(_errorMessage!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loadAccounts,
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadAccounts() async {
    final repository = widget.repository;
    if (repository == null) {
      setState(() {
        _isLoadingAccounts = false;
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _isLoadingAccounts = true;
      _errorMessage = null;
    });

    final result = await repository.getAccounts(
      context: StoreContext(
        storeId: widget.membership.storeId,
        userId: widget.user.id,
      ),
    );
    if (!mounted) {
      return;
    }

    if (result is FailureResult<List<Account>>) {
      setState(() {
        _isLoadingAccounts = false;
        _errorMessage = result.failure.message;
      });
      return;
    }

    if (result is Success<List<Account>>) {
      final accounts =
          result.value.where((account) => account.canPost).toList();
      setState(() {
        _accounts = accounts;
        _selectedAccountId = _selectedAccountId != null &&
                accounts.any((account) => account.id == _selectedAccountId)
            ? _selectedAccountId
            : accounts.firstOrNull?.id;
        _isLoadingAccounts = false;
      });

      final accountId = _selectedAccountId;
      if (accountId != null) {
        await _loadLedger(accountId);
      }
    }
  }

  Future<void> _loadLedger(String accountId) async {
    final repository = widget.repository;
    if (repository == null) {
      return;
    }

    setState(() {
      _isLoadingLedger = true;
      _errorMessage = null;
    });

    final result = await repository.getAccountLedger(
      context: StoreContext(
        storeId: widget.membership.storeId,
        userId: widget.user.id,
      ),
      accountId: accountId,
    );
    if (!mounted) {
      return;
    }

    if (result is FailureResult<List<AccountLedgerLine>>) {
      setState(() {
        _isLoadingLedger = false;
        _errorMessage = result.failure.message;
      });
      return;
    }

    if (result is Success<List<AccountLedgerLine>>) {
      setState(() {
        _isLoadingLedger = false;
        _lines = result.value;
      });
    }
  }

  String _formatDate(DateTime date) {
    final utc = date.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
  }
}
