import 'package:flutter/material.dart';

import '../../../core/money/money.dart';
import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../accounting/domain/entities/account.dart';
import '../../accounting/domain/entities/account_balance_snapshot.dart';
import '../../accounting/domain/entities/account_ledger_line.dart';
import '../../accounting/domain/enums/accounting_enums.dart';
import '../../accounting/domain/repositories/accounting_query_repository.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../domain/repositories/account_transfer_repository.dart';
import 'account_transfers_page.dart';

class CashBanksPage extends StatefulWidget {
  const CashBanksPage({
    required this.accountingQueryRepository,
    required this.transferRepository,
    required this.user,
    required this.membership,
    super.key,
  });

  final AccountingQueryRepository? accountingQueryRepository;
  final AccountTransferRepository? transferRepository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<CashBanksPage> createState() => _CashBanksPageState();
}

class _CashBanksPageState extends State<CashBanksPage> {
  static const _currency = 'ILS';

  List<Account> _accounts = const <Account>[];
  Map<String, AccountBalanceSnapshot> _balances =
      const <String, AccountBalanceSnapshot>{};
  String? _selectedAccountId;
  List<AccountLedgerLine> _ledgerLines = const <AccountLedgerLine>[];
  bool _isLoading = true;
  bool _isLoadingLedger = false;
  String? _errorMessage;

  StoreContext get _context {
    return StoreContext(
      storeId: widget.membership.storeId,
      userId: widget.user.id,
    );
  }

  List<Account> get _treasuryAccounts {
    return _accounts
        .where(
          (account) =>
              account.controlType == ControlType.cashBox ||
              account.controlType == ControlType.bank ||
              account.controlType == ControlType.checks ||
              account.controlType == ControlType.checksPayable ||
              account.controlType == ControlType.cardReceivable,
        )
        .toList(growable: false);
  }

  Account? get _selectedAccount {
    final selectedId = _selectedAccountId;
    if (selectedId == null) {
      return null;
    }
    for (final account in _treasuryAccounts) {
      if (account.id == selectedId) {
        return account;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final queryRepository = widget.accountingQueryRepository;
    if (queryRepository == null) {
      return const Center(
        child: Text('مستودع أرصدة الصناديق والبنوك غير موصول بهذه البيئة.'),
      );
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return _buildErrorState();
    }

    final accounts = _treasuryAccounts;
    if (accounts.isEmpty) {
      return _buildEmptyState();
    }

    final selectedAccount = _selectedAccount;
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
            _buildSummary(context, accounts),
            const SizedBox(height: 12),
            _buildAccounts(context, accounts),
            if (selectedAccount != null) ...[
              const SizedBox(height: 12),
              _buildLedgerCard(context, selectedAccount),
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
        child: Row(
          children: [
            const Icon(Icons.account_balance_wallet_outlined, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'الصناديق والبنوك',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'الأرصدة المعروضة من إسقاط account_balances المرحّل '
                    'من القيود الذرية، والحركة التفصيلية من دفتر الأستاذ.',
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'تحديث',
              onPressed: _isLoading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: widget.transferRepository == null
                  ? null
                  : _openTransferDialog,
              icon: const Icon(Icons.swap_horiz_outlined),
              label: const Text('تحويل داخلي'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(BuildContext context, List<Account> accounts) {
    var liquid = Money.zero(currency: _currency);
    var pending = Money.zero(currency: _currency);
    var obligations = Money.zero(currency: _currency);

    for (final account in accounts) {
      final balance = _balanceFor(account);
      switch (account.controlType) {
        case ControlType.cashBox:
        case ControlType.bank:
          liquid += balance;
        case ControlType.checks:
        case ControlType.cardReceivable:
          pending += balance;
        case ControlType.checksPayable:
          obligations += balance;
        default:
          break;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _summaryTile(
              context,
              title: 'السيولة المباشرة',
              value: liquid,
              icon: Icons.payments_outlined,
            ),
            _summaryTile(
              context,
              title: 'قيد التحصيل',
              value: pending,
              icon: Icons.pending_actions_outlined,
            ),
            _summaryTile(
              context,
              title: 'شيكات صادرة',
              value: obligations,
              icon: Icons.outbox_outlined,
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryTile(
    BuildContext context, {
    required String title,
    required Money value,
    required IconData icon,
  }) {
    return SizedBox(
      width: 220,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title),
        subtitle: Text(
          value.formatted,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }

  Widget _buildAccounts(BuildContext context, List<Account> accounts) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'الحسابات المرتبطة بالسيولة',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'اختَر حساباً لعرض كشف حركته. البطاقة لا تعيد جمع القيود لتحديد '
              'الرصيد الحالي؛ الرصيد المعتمد هو الإسقاط المرحّل.',
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: accounts.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 360,
                mainAxisExtent: 104,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemBuilder: (context, index) {
                final account = accounts[index];
                final selected = account.id == _selectedAccountId;
                return _buildAccountCard(context, account, selected);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountCard(
    BuildContext context,
    Account account,
    bool selected,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: selected ? colorScheme.primaryContainer : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _isLoadingLedger
            ? null
            : () {
                setState(() {
                  _selectedAccountId = account.id;
                  _ledgerLines = const <AccountLedgerLine>[];
                });
                _loadLedger(account);
              },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: selected
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest,
                foregroundColor: selected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
                child: Icon(_iconFor(account.controlType)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '\${account.code} — \${account.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(_controlLabel(account.controlType)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _balanceFor(account).formatted,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLedgerCard(BuildContext context, Account account) {
    final balance = _balanceFor(account);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.book_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'كشف حركة \${account.name}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text(
                  'الرصيد المعتمد: \${balance.formatted}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _isLoadingLedger
                  ? 'جارٍ تحميل الحركة...'
                  : 'الحركة من journal_entries/lines. الرصيد النهائي في البطاقة '
                      'يأتي من account_balances.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_isLoadingLedger)
              const Center(child: CircularProgressIndicator())
            else if (_ledgerLines.isEmpty)
              const Text('لا توجد حركات مرحّلة لهذا الحساب.')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('التاريخ')),
                    DataColumn(label: Text('البيان')),
                    DataColumn(label: Text('مدين')),
                    DataColumn(label: Text('دائن')),
                    DataColumn(label: Text('الحركة')),
                  ],
                  rows: [
                    for (final line in _ledgerLines)
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
                          DataCell(Text(line.movement.formatted)),
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
          Text(_errorMessage!, textAlign: TextAlign.center),
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

  Widget _buildEmptyState() {
    return const Center(
      child: Text('لا توجد حسابات صندوق أو بنك أو تحصيل مرتبطة بهذا المتجر.'),
    );
  }

  Money _balanceFor(Account account) {
    final snapshot = _balances[account.id];
    return snapshot?.normalizedBalance(account.normalSide) ??
        Money.zero(currency: account.currency);
  }

  Future<void> _load() async {
    final repository = widget.accountingQueryRepository;
    if (repository == null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final accountsResult = await repository.getAccounts(context: _context);
    if (!mounted) {
      return;
    }
    if (accountsResult is FailureResult<List<Account>>) {
      setState(() {
        _isLoading = false;
        _errorMessage = accountsResult.failure.message;
      });
      return;
    }

    final balancesResult = await repository.getAccountBalances(
      context: _context,
    );
    if (!mounted) {
      return;
    }
    if (balancesResult is FailureResult<List<AccountBalanceSnapshot>>) {
      setState(() {
        _isLoading = false;
        _errorMessage = balancesResult.failure.message;
      });
      return;
    }

    final accounts = (accountsResult as Success<List<Account>>).value;
    final snapshots =
        (balancesResult as Success<List<AccountBalanceSnapshot>>).value;
    final balances = <String, AccountBalanceSnapshot>{
      for (final snapshot in snapshots) snapshot.accountId: snapshot,
    };
    final treasury = accounts.where((account) {
      return account.controlType == ControlType.cashBox ||
          account.controlType == ControlType.bank ||
          account.controlType == ControlType.checks ||
          account.controlType == ControlType.checksPayable ||
          account.controlType == ControlType.cardReceivable;
    }).toList(growable: false);

    final selectedStillExists = _selectedAccountId != null &&
        treasury.any((account) => account.id == _selectedAccountId);
    setState(() {
      _accounts = accounts;
      _balances = balances;
      _selectedAccountId =
          selectedStillExists ? _selectedAccountId : treasury.firstOrNull?.id;
      _ledgerLines = const <AccountLedgerLine>[];
      _isLoading = false;
    });

    final selected = _selectedAccount;
    if (selected != null) {
      await _loadLedger(selected);
    }
  }

  Future<void> _loadLedger(Account account) async {
    final repository = widget.accountingQueryRepository;
    if (repository == null) {
      return;
    }

    setState(() => _isLoadingLedger = true);
    final result = await repository.getAccountLedger(
      context: _context,
      accountId: account.id,
      limit: 500,
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
        _ledgerLines = result.value;
        _isLoadingLedger = false;
      });
    }
  }

  Future<void> _openTransferDialog() async {
    final repository = widget.transferRepository;
    if (repository == null) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          child: SizedBox(
            width: 720,
            height: 680,
            child: AccountTransfersPage(
              repository: repository,
              user: widget.user,
              membership: widget.membership,
            ),
          ),
        );
      },
    );
    if (mounted) {
      await _load();
    }
  }

  IconData _iconFor(ControlType controlType) {
    switch (controlType) {
      case ControlType.cashBox:
        return Icons.point_of_sale_outlined;
      case ControlType.bank:
        return Icons.account_balance_outlined;
      case ControlType.checks:
        return Icons.payments_outlined;
      case ControlType.checksPayable:
        return Icons.outbox_outlined;
      case ControlType.cardReceivable:
        return Icons.credit_card_outlined;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }

  String _controlLabel(ControlType controlType) {
    switch (controlType) {
      case ControlType.cashBox:
        return 'صندوق';
      case ControlType.bank:
        return 'بنك';
      case ControlType.checks:
        return 'شيكات قيد التحصيل';
      case ControlType.checksPayable:
        return 'شيكات صادرة';
      case ControlType.cardReceivable:
        return 'بطاقات قيد التحصيل';
      default:
        return 'حساب سيولة';
    }
  }

  String _formatDate(DateTime date) {
    final utc = date.toUtc();
    return '\${utc.year.toString().padLeft(4, '0')}-'
        '\${utc.month.toString().padLeft(2, '0')}-'
        '\${utc.day.toString().padLeft(2, '0')}';
  }
}
