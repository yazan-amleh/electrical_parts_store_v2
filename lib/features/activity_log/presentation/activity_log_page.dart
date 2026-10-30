import 'package:flutter/material.dart';

import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../domain/entities/activity_log.dart';
import '../domain/repositories/activity_log_repository.dart';

enum _ActivityPeriod {
  today,
  week,
  all,
  custom,
}

class ActivityLogPage extends StatefulWidget {
  const ActivityLogPage({
    required this.repository,
    required this.user,
    required this.membership,
    super.key,
  });

  final ActivityLogRepository repository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<ActivityLogPage> createState() => _ActivityLogPageState();
}

class _ActivityLogPageState extends State<ActivityLogPage> {
  static const _loadLimit = 500;

  final _searchController = TextEditingController();

  late Stream<Result<List<ActivityLog>>> _logs;
  _ActivityPeriod _period = _ActivityPeriod.today;
  ActivityType? _selectedType;
  DateTimeRange? _customRange;
  String _searchQuery = '';

  StoreContext get _context => StoreContext(
        storeId: widget.membership.storeId,
        userId: widget.user.id,
      );

  @override
  void initState() {
    super.initState();
    _bindStream();
  }

  @override
  void didUpdateWidget(covariant ActivityLogPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.id != widget.user.id ||
        oldWidget.membership.storeId != widget.membership.storeId ||
        oldWidget.repository != widget.repository) {
      _searchController.clear();
      _searchQuery = '';
      _selectedType = null;
      _period = _ActivityPeriod.today;
      _customRange = null;
      _bindStream();
    }
  }

  void _bindStream() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime? fromInclusive;
    DateTime? toExclusive;

    switch (_period) {
      case _ActivityPeriod.today:
        fromInclusive = today;
        toExclusive = today.add(const Duration(days: 1));
        break;
      case _ActivityPeriod.week:
        fromInclusive = today.subtract(Duration(days: today.weekday - 1));
        toExclusive = fromInclusive.add(const Duration(days: 7));
        break;
      case _ActivityPeriod.custom:
        final range = _customRange;
        if (range != null) {
          fromInclusive = DateTime(
            range.start.year,
            range.start.month,
            range.start.day,
          );
          toExclusive = DateTime(
            range.end.year,
            range.end.month,
            range.end.day + 1,
          );
        }
        break;
      case _ActivityPeriod.all:
        break;
    }

    _logs = widget.repository.watchLogs(
      context: _context,
      limit: _loadLimit,
      fromInclusive: fromInclusive?.toUtc(),
      toExclusive: toExclusive?.toUtc(),
    );
  }

  Future<void> _refresh() async {
    setState(_bindStream);
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('سجل النشاطات'),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
            if (_period == _ActivityPeriod.custom)
              IconButton(
                tooltip: 'تحديد المدة',
                onPressed: _pickCustomRange,
                icon: const Icon(Icons.date_range_outlined),
              ),
          ],
        ),
        body: Column(
          children: [
            _buildSearchAndTypeFilter(),
            _buildPeriodFilter(),
            if (_period == _ActivityPeriod.custom && _customRange != null)
              _buildCustomRangeSummary(),
            Expanded(
              child: StreamBuilder<Result<List<ActivityLog>>>(
                stream: _logs,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _ErrorState(message: snapshot.error.toString());
                  }

                  final result = snapshot.data;
                  if (result is FailureResult<List<ActivityLog>>) {
                    return _ErrorState(message: result.failure.message);
                  }

                  final loaded = result is Success<List<ActivityLog>>
                      ? result.value
                      : const <ActivityLog>[];
                  final visible = _applyFilters(loaded);

                  return Column(
                    children: [
                      if (loaded.length >= _loadLimit)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: MaterialBanner(
                            content: Text(
                              'يتم عرض أحدث 500 حدث ضمن الفترة المحددة فقط. '
                              'البحث وتصفية النوع يعملان على الأحداث المحمّلة.',
                            ),
                            actions: [SizedBox.shrink()],
                          ),
                        ),
                      Expanded(
                        child: visible.isEmpty
                            ? _EmptyState(
                                hasFilters: _hasActiveFilters,
                                onClear: _clearFilters,
                              )
                            : RefreshIndicator(
                                onRefresh: _refresh,
                                child: ListView.separated(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 4, 12, 20),
                                  itemCount: visible.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 6),
                                  itemBuilder: (context, index) {
                                    return _buildActivityCard(visible[index]);
                                  },
                                ),
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndTypeFilter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            children: [
              const Icon(Icons.search),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'بحث في سجل النشاطات...',
                    border: InputBorder.none,
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value.trim());
                  },
                ),
              ),
              if (_searchQuery.isNotEmpty)
                IconButton(
                  tooltip: 'مسح البحث',
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  icon: const Icon(Icons.clear),
                ),
              PopupMenuButton<String>(
                tooltip: 'تصفية حسب النوع',
                icon: Icon(
                  Icons.filter_list,
                  color: _selectedType == null
                      ? null
                      : Theme.of(context).colorScheme.primary,
                ),
                onSelected: (value) {
                  setState(() {
                    _selectedType = value == '__all__'
                        ? null
                        : ActivityType.values.firstWhere(
                            (type) => type.name == value,
                          );
                  });
                },
                itemBuilder: (context) => [
                  const PopupMenuItem<String>(
                    value: '__all__',
                    child: Text('كل الأنواع'),
                  ),
                  ...ActivityType.values.map(
                    (type) => PopupMenuItem<String>(
                      value: type.name,
                      child: Row(
                        children: [
                          Icon(_iconFor(type), size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text(type.arabicLabel)),
                          if (_selectedType == type)
                            const Icon(Icons.check, size: 18),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _periodChip(_ActivityPeriod.today, 'اليوم'),
          const SizedBox(width: 6),
          _periodChip(_ActivityPeriod.week, 'هذا الأسبوع'),
          const SizedBox(width: 6),
          _periodChip(_ActivityPeriod.all, 'الكل'),
          const SizedBox(width: 6),
          _periodChip(_ActivityPeriod.custom, 'مدة مخصصة'),
        ],
      ),
    );
  }

  Widget _periodChip(_ActivityPeriod period, String label) {
    return ChoiceChip(
      selected: _period == period,
      label: Text(label),
      onSelected: (_) async {
        if (period == _ActivityPeriod.custom && _customRange == null) {
          await _pickCustomRange();
          return;
        }
        setState(() {
          _period = period;
          _bindStream();
        });
      },
    );
  }

  Widget _buildCustomRangeSummary() {
    final range = _customRange!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Card(
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.date_range_outlined),
          title: Text(
            'من ${_formatDateOnly(range.start)} إلى '
            '${_formatDateOnly(range.end)}',
          ),
          trailing: TextButton(
            onPressed: _pickCustomRange,
            child: const Text('تغيير'),
          ),
        ),
      ),
    );
  }

  List<ActivityLog> _applyFilters(List<ActivityLog> logs) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final startOfNextWeek = startOfWeek.add(const Duration(days: 7));
    final query = _searchQuery.toLowerCase();

    return logs.where((log) {
      if (_selectedType != null && log.type != _selectedType) {
        return false;
      }

      final local = log.occurredAt.toLocal();
      switch (_period) {
        case _ActivityPeriod.today:
          if (local.year != today.year ||
              local.month != today.month ||
              local.day != today.day) {
            return false;
          }
          break;
        case _ActivityPeriod.week:
          if (local.isBefore(startOfWeek) || !local.isBefore(startOfNextWeek)) {
            return false;
          }
          break;
        case _ActivityPeriod.custom:
          final range = _customRange;
          if (range == null) {
            break;
          }
          final start = DateTime(
            range.start.year,
            range.start.month,
            range.start.day,
          );
          final endExclusive = DateTime(
            range.end.year,
            range.end.month,
            range.end.day,
          ).add(const Duration(days: 1));
          if (local.isBefore(start) || !local.isBefore(endExclusive)) {
            return false;
          }
          break;
        case _ActivityPeriod.all:
          break;
      }

      if (query.isEmpty) {
        return true;
      }
      final haystack = <String>[
        log.description,
        log.type.arabicLabel,
        log.userName ?? '',
        log.userId ?? '',
        log.metadata.toString(),
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);
  }

  Widget _buildActivityCard(ActivityLog log) {
    final actor = log.userName?.trim().isNotEmpty == true
        ? log.userName!
        : log.userId?.trim().isNotEmpty == true
            ? log.userId!
            : 'مستخدم النظام';

    return Card(
      child: ListTile(
        onTap: () => _showDetails(log),
        leading: CircleAvatar(
          child: Icon(_iconFor(log.type)),
        ),
        title: Text(log.type.arabicLabel),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 3),
            Text(
              log.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 5),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                _MetaLabel(icon: Icons.person_outline, text: actor),
                _MetaLabel(
                  icon: Icons.access_time,
                  text: _formatDateTime(log.occurredAt),
                ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_left),
      ),
    );
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final initial = _customRange ??
        DateTimeRange(
          start: now.subtract(const Duration(days: 6)),
          end: now,
        );
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: initial,
      helpText: 'تحديد الفترة الزمنية',
      cancelText: 'إلغاء',
      confirmText: 'تطبيق',
      saveText: 'تطبيق',
    );
    if (!mounted || selected == null) {
      return;
    }
    setState(() {
      _period = _ActivityPeriod.custom;
      _customRange = selected;
      _bindStream();
    });
  }

  void _showDetails(ActivityLog log) {
    final actor = log.userName?.trim().isNotEmpty == true
        ? log.userName!
        : log.userId?.trim().isNotEmpty == true
            ? log.userId!
            : 'مستخدم النظام';

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              CircleAvatar(child: Icon(_iconFor(log.type))),
              const SizedBox(width: 10),
              Expanded(child: Text(log.type.arabicLabel)),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DetailRow(
                    label: 'الوصف',
                    value: log.description,
                  ),
                  _DetailRow(
                    label: 'التاريخ والوقت',
                    value: _formatDateTime(log.occurredAt),
                  ),
                  _DetailRow(
                    label: 'تم بواسطة',
                    value: actor,
                  ),
                  if (log.metadata.isNotEmpty) ...[
                    const Divider(height: 28),
                    Text(
                      'تفاصيل إضافية',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    for (final entry in log.metadata.entries)
                      _DetailRow(
                        label: _metadataLabel(entry.key),
                        value: '${entry.value}',
                      ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إغلاق'),
            ),
          ],
        );
      },
    );
  }

  bool get _hasActiveFilters {
    return _searchQuery.isNotEmpty ||
        _selectedType != null ||
        _period != _ActivityPeriod.all;
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _selectedType = null;
      _period = _ActivityPeriod.all;
      _customRange = null;
      _bindStream();
    });
  }

  String _metadataLabel(String key) {
    switch (key) {
      case 'source':
        return 'المصدر';
      case 'sourceId':
        return 'رقم المرجع';
      case 'operation':
        return 'نوع التغيير';
      default:
        return key.replaceAll('_', ' ');
    }
  }

  IconData _iconFor(ActivityType type) {
    switch (type) {
      case ActivityType.saleCreated:
        return Icons.point_of_sale_outlined;
      case ActivityType.purchasePosted:
        return Icons.shopping_cart_outlined;
      case ActivityType.paymentPosted:
        return Icons.payments_outlined;
      case ActivityType.customerChanged:
        return Icons.people_outline;
      case ActivityType.supplierChanged:
        return Icons.local_shipping_outlined;
      case ActivityType.productChanged:
        return Icons.inventory_2_outlined;
      case ActivityType.categoryChanged:
        return Icons.category_outlined;
      case ActivityType.offerChanged:
        return Icons.request_quote_outlined;
      case ActivityType.expensePosted:
        return Icons.receipt_long_outlined;
      case ActivityType.repairChanged:
        return Icons.build_outlined;
      case ActivityType.accountingPosted:
        return Icons.account_balance_outlined;
      case ActivityType.system:
        return Icons.settings_outlined;
      case ActivityType.other:
        return Icons.info_outline;
    }
  }

  String _formatDateOnly(DateTime value) {
    final local = value.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$day/$month/$year';
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${_formatDateOnly(local)} $hour:$minute';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

class _MetaLabel extends StatelessWidget {
  const _MetaLabel({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14),
        const SizedBox(width: 4),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 2),
          SelectableText(value),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            const Text('تعذر تحميل سجل النشاطات.'),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.hasFilters,
    required this.onClear,
  });

  final bool hasFilters;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history_toggle_off_outlined, size: 56),
            const SizedBox(height: 12),
            const Text('لا توجد نشاطات مطابقة.'),
            if (hasFilters) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('إلغاء البحث والفلاتر'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
