import 'package:flutter/material.dart';

import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../domain/entities/voucher_record.dart';
import '../domain/repositories/voucher_query_repository.dart';

class VoucherRegisterPage extends StatefulWidget {
  const VoucherRegisterPage({
    required this.repository,
    required this.user,
    required this.membership,
    super.key,
  });

  final VoucherQueryRepository? repository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<VoucherRegisterPage> createState() => _VoucherRegisterPageState();
}

class _VoucherRegisterPageState extends State<VoucherRegisterPage> {
  final _searchController = TextEditingController();
  List<VoucherRecord> _records = const [];
  VoucherCursor? _nextCursor;
  bool _hasMore = false;
  bool _loading = false;
  int _requestEpoch = 0;
  String? _error;
  String _direction = 'all';
  String _status = 'all';

  @override
  void initState() {
    super.initState();
    _loadPage(reset: true);
  }

  @override
  void didUpdateWidget(covariant VoucherRegisterPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.membership.storeId != widget.membership.storeId ||
        oldWidget.user.id != widget.user.id) {
      _loadPage(reset: true);
    }
  }

  Future<void> _loadPage({bool reset = false}) async {
    final repository = widget.repository;
    if (repository == null || (_loading && !reset)) return;
    final epoch = ++_requestEpoch;
    final requestedStoreId = widget.membership.storeId;
    final requestedUserId = widget.user.id;
    final cursor = reset ? null : _nextCursor;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _records = const [];
        _nextCursor = null;
        _hasMore = false;
      }
    });
    try {
      final result = await repository.getVoucherPage(
        context: StoreContext(
          storeId: requestedStoreId,
          userId: requestedUserId,
        ),
        after: cursor,
      );
      if (!mounted ||
          epoch != _requestEpoch ||
          requestedStoreId != widget.membership.storeId ||
          requestedUserId != widget.user.id) {
        return;
      }
      if (result is FailureResult<VoucherPage>) {
        setState(() => _error = result.failure.message);
      } else if (result is Success<VoucherPage>) {
        final knownIds = _records.map((item) => item.id).toSet();
        final additions = result.value.records
            .where((item) => knownIds.add(item.id))
            .toList();
        setState(() {
          _records = [..._records, ...additions];
          _hasMore = result.value.hasMore;
          _nextCursor = result.value.nextCursor;
        });
      }
    } catch (error) {
      if (mounted && epoch == _requestEpoch) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && epoch == _requestEpoch) {
        setState(() => _loading = false);
      }
    }
  }

  List<VoucherRecord> get _visibleRecords {
    final search = _searchController.text.trim().toLowerCase();
    return _records.where((record) {
      if (_direction == 'receipt' && !record.isReceipt) return false;
      if (_direction == 'payment' && record.isReceipt) return false;
      if (_status != 'all' && record.status != _status) return false;
      return search.isEmpty ||
          record.id.toLowerCase().contains(search) ||
          record.partyId.toLowerCase().contains(search) ||
          record.journalEntryId.toLowerCase().contains(search) ||
          (record.description?.toLowerCase().contains(search) ?? false);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.repository == null) {
      return const Center(
        child: Text('مستودع سجل السندات غير موصول بهذه البيئة.'),
      );
    }
    final records = _visibleRecords;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'بحث برقم الحركة أو الطرف أو القيد',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              DropdownButton<String>(
                value: _direction,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('القبض والدفع')),
                  DropdownMenuItem(value: 'receipt', child: Text('قبض فقط')),
                  DropdownMenuItem(value: 'payment', child: Text('دفع فقط')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _direction = value);
                },
              ),
              DropdownButton<String>(
                value: _status,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('كل الحالات')),
                  DropdownMenuItem(value: 'posted', child: Text('مرحّل')),
                  DropdownMenuItem(
                      value: 'pending', child: Text('شيك قيد التحصيل')),
                  DropdownMenuItem(value: 'cleared', child: Text('شيك محصّل')),
                  DropdownMenuItem(value: 'bounced', child: Text('شيك مرتجع')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _status = value);
                },
              ),
              IconButton(
                tooltip: 'تحديث السندات',
                onPressed: _loading ? null : () => _loadPage(reset: true),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'المعروض ${records.length} من ${_records.length} سند محمّل. '
            'البحث والفلاتر على الصفحات المحمّلة فقط. '
            'مرجع السند الحالي هو معرّف الحركة وليس رقمًا تسلسليًا.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: _loading && _records.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : records.isEmpty
                  ? const Center(
                      child: Text('لا توجد سندات مطابقة في الصفحات المحمّلة.'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: records.length,
                      itemBuilder: (context, index) {
                        final item = records[index];
                        return Card(
                          child: ListTile(
                            leading: Icon(
                              item.isReceipt
                                  ? Icons.south_west_rounded
                                  : Icons.north_east_rounded,
                            ),
                            title: Text(
                              '${item.typeLabel} · ${item.amount.formatted}',
                            ),
                            subtitle: Text(
                              'الرقم: ${item.voucherNumber ?? 'غير مرقم (قديم)'}\n'
                              'المرجع: ${item.id}\n'
                              'الطرف: ${item.partyId} · ${item.statusLabel}\n'
                              'القيد: ${item.journalEntryId} · '
                              '${item.postedAt.toLocal().toString().split('.').first}',
                            ),
                            isThreeLine: true,
                          ),
                        );
                      },
                    ),
        ),
        if (_hasMore)
          Padding(
            padding: const EdgeInsets.all(8),
            child: OutlinedButton.icon(
              onPressed: _loading ? null : () => _loadPage(),
              icon: _loading
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more),
              label: const Text('تحميل 50 سندًا إضافيًا'),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
