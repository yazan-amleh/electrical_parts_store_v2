import 'package:flutter/material.dart';

import '../../../core/money/money.dart';
import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../domain/entities/party.dart';
import '../domain/entities/party_ledger_entry.dart';
import '../domain/enums/party_type.dart';
import '../domain/repositories/party_ledger_repository.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';

class PartyLedgerPage extends StatefulWidget {
  const PartyLedgerPage({
    required this.repository,
    required this.user,
    required this.membership,
    required this.party,
    super.key,
  });

  final PartyLedgerRepository repository;
  final AuthenticatedUser user;
  final StoreMembership membership;
  final Party party;

  @override
  State<PartyLedgerPage> createState() => _PartyLedgerPageState();
}

class _PartyLedgerPageState extends State<PartyLedgerPage> {
  List<PartyLedgerEntry> _entries = const <PartyLedgerEntry>[];
  Money _balance = const Money.zero();
  bool _isLoading = true;
  String? _errorMessage;
  int _loadEpoch = 0;

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
  void didUpdateWidget(covariant PartyLedgerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.id != widget.user.id ||
        oldWidget.membership.storeId != widget.membership.storeId ||
        oldWidget.party.id != widget.party.id ||
        oldWidget.party.type != widget.party.type) {
      _entries = const <PartyLedgerEntry>[];
      _balance = const Money.zero();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCustomer = widget.party.type == PartyType.customer;
    if (_isLoading) {
      return const SizedBox(
        width: 760,
        height: 560,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_errorMessage != null) {
      return SizedBox(width: 760, height: 560, child: _buildErrorState());
    }

    final loadedDelta = _entries.fold(
      Money.zero(currency: _balance.currency),
      (sum, entry) => sum + entry.balanceDelta,
    );
    final openingBalance = _balance - loadedDelta;
    var running = openingBalance;
    final rows = <_PartyLedgerRow>[];
    for (final entry in _entries) {
      running = running + entry.balanceDelta;
      rows.add(_PartyLedgerRow(entry: entry, runningBalance: running));
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: SizedBox(
        width: 760,
        height: 620,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Icon(
                    isCustomer
                        ? Icons.people_outline
                        : Icons.local_shipping_outlined,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isCustomer ? 'كشف حساب العميل' : 'كشف حساب المورد',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'تحديث',
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Card(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: ListTile(
                title: Text(widget.party.name),
                subtitle: Text(
                  isCustomer
                      ? 'الرصيد المستحق على العميل'
                      : 'الرصيد المستحق للمورد',
                ),
                trailing: Text(
                  _balance.formatted,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            if (_entries.length == 500)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'يعرض الكشف آخر 500 حركة فقط. تم احتساب الرصيد الافتتاحي '
                  'من الرصيد الحالي حتى تبقى الأرصدة الجارية متطابقة.',
                ),
              ),
            Expanded(
              child: _entries.isEmpty
                  ? const Center(child: Text('لا توجد حركات لهذا الطرف.'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) =>
                          _buildEntryCard(rows[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryCard(_PartyLedgerRow row) {
    final entry = row.entry;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _sourceLabel(entry.sourceType),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(_formatDate(entry.postedAt)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              entry.description?.trim().isNotEmpty == true
                  ? entry.description!
                  : 'بدون وصف',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _amount('مدين', entry.debit),
                _amount('دائن', entry.credit),
                _amount('الرصيد الجاري', row.runningBalance),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _amount(String label, Money amount) {
    return Chip(label: Text('$label: ${amount.formatted}'));
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
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
      ),
    );
  }

  Future<void> _load() async {
    final epoch = ++_loadEpoch;
    final requestedStore = widget.membership.storeId;
    final requestedUser = widget.user.id;
    final requestedPartyId = widget.party.id;
    final requestedPartyType = widget.party.type;

    if (widget.party.storeId != requestedStore) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'الطرف لا ينتمي إلى المتجر الحالي.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final entriesResult = await widget.repository.getEntries(
      context: _storeContext,
      partyType: requestedPartyType,
      partyId: requestedPartyId,
      limit: 500,
    );
    if (!mounted ||
        epoch != _loadEpoch ||
        requestedStore != widget.membership.storeId ||
        requestedUser != widget.user.id ||
        requestedPartyId != widget.party.id ||
        requestedPartyType != widget.party.type) {
      return;
    }
    if (entriesResult is FailureResult<List<PartyLedgerEntry>>) {
      setState(() {
        _isLoading = false;
        _errorMessage = entriesResult.failure.message;
      });
      return;
    }
    final balanceResult = await widget.repository.getBalance(
      context: _storeContext,
      partyType: requestedPartyType,
      partyId: requestedPartyId,
    );
    if (!mounted ||
        epoch != _loadEpoch ||
        requestedStore != widget.membership.storeId ||
        requestedUser != widget.user.id ||
        requestedPartyId != widget.party.id ||
        requestedPartyType != widget.party.type) {
      return;
    }
    if (balanceResult is FailureResult<Money>) {
      setState(() {
        _isLoading = false;
        _errorMessage = balanceResult.failure.message;
      });
      return;
    }
    final entries = (entriesResult as Success<List<PartyLedgerEntry>>).value;
    final balance = (balanceResult as Success<Money>).value;
    if (entries.any(
      (entry) =>
          entry.debit.currency != balance.currency ||
          entry.credit.currency != balance.currency,
    )) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'عملة كشف الحساب لا تطابق رصيد الطرف.';
      });
      return;
    }
    setState(() {
      _entries = entries;
      _balance = balance;
      _isLoading = false;
    });
  }

  String _sourceLabel(String sourceType) {
    switch (sourceType) {
      case 'sale':
        return 'بيع آجل';
      case 'purchase':
        return 'شراء آجل';
      case 'customerReceipt':
        return 'قبض من العميل';
      case 'supplierPayment':
        return 'دفع للمورد';
      default:
        return sourceType;
    }
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
  }
}

class _PartyLedgerRow {
  const _PartyLedgerRow({required this.entry, required this.runningBalance});

  final PartyLedgerEntry entry;
  final Money runningBalance;
}
