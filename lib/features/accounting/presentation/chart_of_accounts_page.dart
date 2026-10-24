import 'package:flutter/material.dart';

import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../domain/entities/account.dart';
import '../domain/enums/accounting_enums.dart';
import '../../auth/domain/enums/store_role.dart';
import '../data/repositories/firestore_chart_mutation_repository.dart';
import '../domain/repositories/accounting_query_repository.dart';

class ChartOfAccountsPage extends StatefulWidget {
  const ChartOfAccountsPage({
    required this.repository,
    this.mutationRepository,
    required this.user,
    required this.membership,
    super.key,
  });

  final AccountingQueryRepository? repository;
  final FirestoreChartMutationRepository? mutationRepository;
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
  bool _isSaving = false;

  bool get _mayChangeChart =>
      widget.mutationRepository != null &&
      widget.membership.isActive &&
      widget.membership.role.canManageStore;

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
            if (_isSaving) const CircularProgressIndicator(),
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
        trailing: _mayChangeChart
            ? Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (account.isHeader)
                    IconButton(
                      tooltip: 'إضافة حساب فرعي',
                      onPressed:
                          _isSaving ? null : () => _addChildAccount(account),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  IconButton(
                    tooltip: 'تعديل اسم الحساب',
                    onPressed: _isSaving ? null : () => _renameAccount(account),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              )
            : account.canPost
                ? const Chip(label: Text('ترحيل'))
                : const Chip(label: Text('تجميعي')),
      ),
    );
  }

  StoreContext get _storeContext => StoreContext(
        storeId: widget.membership.storeId,
        userId: widget.user.id,
      );

  Future<void> _renameAccount(Account account) async {
    final controller = TextEditingController(text: account.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تعديل اسم الحساب'),
        content: TextField(
          controller: controller,
          maxLength: 160,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'اسم الحساب'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted ||
        name == null ||
        name.trim().isEmpty ||
        name.trim() == account.name ||
        !_mayChangeChart) {
      return;
    }
    setState(() => _isSaving = true);
    final result = await widget.mutationRepository!.updateAccountMetadata(
      context: _storeContext,
      accountId: account.id,
      changes: {'name': name.trim()},
    );
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (result is FailureResult<String>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.failure.message)),
      );
      return;
    }
    await _loadAccounts();
  }

  Future<void> _addChildAccount(Account parent) async {
    if (!_mayChangeChart || !parent.isHeader) return;
    final idController = TextEditingController();
    final nameController = TextEditingController();
    final input = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('إضافة حساب فرعي إلى ${parent.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: idController,
              maxLength: 128,
              decoration: const InputDecoration(labelText: 'رقم الحساب'),
            ),
            TextField(
              controller: nameController,
              maxLength: 160,
              decoration: const InputDecoration(labelText: 'اسم الحساب'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
                dialogContext, [idController.text, nameController.text]),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
    idController.dispose();
    nameController.dispose();
    if (!mounted || input == null || !_mayChangeChart) return;
    final id = input[0].trim();
    final name = input[1].trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id) || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رقم الحساب أو اسمه غير صالح')),
      );
      return;
    }
    setState(() => _isSaving = true);
    final result = await widget.mutationRepository!.createAccount(
      context: _storeContext,
      account: Account(
        id: id,
        storeId: widget.membership.storeId,
        code: id,
        name: name,
        type: parent.type,
        normalSide: parent.normalSide,
        controlType: ControlType.none,
        statementSection: parent.statementSection,
        parentId: parent.id,
        currency: parent.currency,
        sortOrder: parent.sortOrder + 1,
      ),
    );
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (result is FailureResult<Account>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.failure.message)),
      );
      return;
    }
    await _loadAccounts();
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
