import 'package:flutter/material.dart';

import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../domain/entities/account.dart';
import '../domain/repositories/accounting_query_repository.dart';

class ChartOfAccountsPage extends StatefulWidget {
  const ChartOfAccountsPage({
    required this.repository,
    required this.user,
    required this.membership,
    super.key,
  });

  final AccountingQueryRepository? repository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<ChartOfAccountsPage> createState() => _ChartOfAccountsPageState();
}

class _ChartOfAccountsPageState extends State<ChartOfAccountsPage> {
  final _searchController = TextEditingController();

  List<Account> _accounts = const <Account>[];
  bool _isLoading = true;
  String? _errorMessage;

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
        child: Text('مستودع شجرة الحسابات غير موصول بهذه البيئة.'),
      );
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return _buildErrorState();
    }

    final accounts = _filteredAccounts;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: accounts.isEmpty
                ? const Center(child: Text('لا توجد حسابات مطابقة.'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    itemCount: accounts.length,
                    itemBuilder: (context, index) =>
                        _buildAccountTile(accounts[index]),
                  ),
          ),
        ],
      ),
    );
  }

  List<Account> get _filteredAccounts {
    final search = _searchController.text.trim().toLowerCase();
    if (search.isEmpty) {
      return _orderedAccounts(_accounts);
    }

    return _orderedAccounts(
      _accounts
          .where(
            (account) =>
                account.code.toLowerCase().contains(search) ||
                account.name.toLowerCase().contains(search),
          )
          .toList(growable: false),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.account_tree_outlined),
            const SizedBox(width: 10),
            Text(
              'شجرة الحسابات',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'ابحث برقم الحساب أو اسمه',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loadAccounts,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountTile(Account account) {
    final depth = _depthOf(account);
    return Card(
      margin: EdgeInsetsDirectional.fromSTEB(12 + depth * 24, 3, 12, 3),
      child: ListTile(
        leading: Icon(
          account.isHeader
              ? Icons.folder_outlined
              : Icons.account_balance_outlined,
        ),
        title: Row(
          children: [
            Text(
              account.code,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(account.name)),
          ],
        ),
        subtitle: Text(account.isHeader ? 'حساب رئيسي' : 'حساب ترحيل'),
        trailing: account.canPost
            ? const Chip(label: Text('ترحيل'))
            : const Chip(label: Text('تجميعي')),
      ),
    );
  }

  List<Account> _orderedAccounts(List<Account> accounts) {
    final byParent = <String?, List<Account>>{};
    for (final account in accounts) {
      byParent.putIfAbsent(account.parentId, () => <Account>[]).add(account);
    }

    for (final children in byParent.values) {
      children.sort((left, right) {
        final order = left.sortOrder.compareTo(right.sortOrder);
        return order == 0 ? left.code.compareTo(right.code) : order;
      });
    }

    final ordered = <Account>[];

    void append(String? parentId) {
      for (final account in byParent[parentId] ?? const <Account>[]) {
        ordered.add(account);
        append(account.id);
      }
    }

    append(null);
    return ordered;
  }

  int _depthOf(Account account) {
    var depth = 0;
    var parentId = account.parentId;
    final visited = <String>{account.id};
    while (parentId != null && visited.add(parentId)) {
      depth++;
      Account? parent;
      for (final candidate in _accounts) {
        if (candidate.id == parentId) {
          parent = candidate;
          break;
        }
      }
      parentId = parent?.parentId;
    }
    return depth;
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
        _isLoading = false;
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await repository.getAccounts(
      context: StoreContext(
        storeId: widget.membership.storeId,
        userId: widget.user.id,
      ),
      includeInactive: true,
    );
    if (!mounted) {
      return;
    }

    if (result is FailureResult<List<Account>>) {
      setState(() {
        _isLoading = false;
        _errorMessage = result.failure.message;
      });
      return;
    }

    if (result is Success<List<Account>>) {
      setState(() {
        _isLoading = false;
        _accounts = result.value;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
