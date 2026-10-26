import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/domain/enums/store_role.dart';

/// V1-inspired, user-customizable shortcut cards. Only targets with V2 pages
/// are offered; the shell resolves destinations and the backend enforces access.
class DashboardQuickAccess extends StatefulWidget {
  const DashboardQuickAccess({
    required this.storeId,
    required this.userId,
    required this.role,
    required this.onOpenModule,
    super.key,
  });

  final String storeId;
  final String userId;
  final StoreRole role;
  final ValueChanged<String> onOpenModule;

  @override
  State<DashboardQuickAccess> createState() => _DashboardQuickAccessState();
}

class _DashboardQuickAccessState extends State<DashboardQuickAccess> {
  static const _shortcuts = <_DashboardShortcut>[
    _DashboardShortcut('sales', 'المبيعات', Icons.point_of_sale_outlined),
    _DashboardShortcut(
      'vouchers-hub',
      'السندات المالية',
      Icons.receipt_long_outlined,
    ),
    _DashboardShortcut(
      'purchase-orders',
      'طلبيات الشراء',
      Icons.shopping_cart_outlined,
    ),
    _DashboardShortcut('purchases', 'المشتريات', Icons.receipt_long_outlined),
    _DashboardShortcut('products', 'الأصناف', Icons.inventory_2_outlined),
    _DashboardShortcut('inventory', 'المخزون', Icons.inventory_outlined),
    _DashboardShortcut('categories', 'التصنيفات', Icons.category_outlined),
    _DashboardShortcut('customers', 'العملاء', Icons.people_outline),
    _DashboardShortcut('suppliers', 'الموردون', Icons.local_shipping_outlined),
    _DashboardShortcut('offers', 'العروض', Icons.local_offer_outlined),
    _DashboardShortcut(
        'cash-banks', 'الصناديق والبنوك', Icons.savings_outlined),
    _DashboardShortcut('checks', 'الشيكات', Icons.payments_outlined),
    _DashboardShortcut(
        'chart-of-accounts', 'شجرة الحسابات', Icons.account_tree),
    _DashboardShortcut('journal', 'قيود اليومية', Icons.menu_book_outlined),
    _DashboardShortcut(
        'trial-balance', 'ميزان المراجعة', Icons.balance_outlined),
    _DashboardShortcut('reports', 'التقارير', Icons.assessment_outlined),
    _DashboardShortcut('notes', 'الملاحظات', Icons.note_alt_outlined),
    _DashboardShortcut('settings', 'إعدادات المتجر', Icons.settings_outlined),
  ];

  List<String> _visibleIds = const [];
  bool _loading = true;
  bool _saving = false;
  int _selectionEpoch = 0;

  String get _preferenceKey =>
      'v2:dashboard-shortcuts:${widget.storeId}:${widget.userId}';

  bool _allowed(_DashboardShortcut item) {
    switch (item.id) {
      case 'sales':
      case 'offers':
        return widget.role.canManageSales;
      case 'purchases':
      case 'purchase-orders':
      case 'products':
      case 'inventory':
      case 'categories':
        return widget.role.canManageInventory;
      case 'journal':
        return widget.role.canPostAccounting;
      case 'settings':
        return widget.role.canManageStore;
      default:
        return true;
    }
  }

  List<_DashboardShortcut> get _available =>
      _shortcuts.where(_allowed).toList(growable: false);

  @override
  void initState() {
    super.initState();
    _loadSelection();
  }

  @override
  void didUpdateWidget(covariant DashboardQuickAccess oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storeId != widget.storeId ||
        oldWidget.userId != widget.userId ||
        oldWidget.role != widget.role) {
      _loadSelection();
    }
  }

  Future<void> _loadSelection() async {
    final epoch = ++_selectionEpoch;
    final preferenceKey = _preferenceKey;
    setState(() => _loading = true);
    final defaults = _available.take(8).map((item) => item.id).toList();
    List<String>? saved;
    try {
      final prefs = await SharedPreferences.getInstance();
      saved = prefs.getStringList(preferenceKey);
    } catch (_) {
      // Shortcuts remain usable if local preferences cannot be read.
    }
    if (!mounted || epoch != _selectionEpoch) return;
    final allowedIds = _available.map((item) => item.id).toSet();
    final selected = (saved ?? defaults)
        .where(allowedIds.contains)
        .toSet()
        .toList(growable: false);
    setState(() {
      _visibleIds = selected.isEmpty ? defaults : selected;
      _loading = false;
    });
  }

  Future<void> _customize() async {
    if (_loading || _saving) return;
    final preferenceKey = _preferenceKey;
    final available = _available;
    final order = List<String>.from(_visibleIds);
    final selected = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, updateDialog) => AlertDialog(
          title: const Text('تخصيص اختصارات لوحة التحكم'),
          content: SizedBox(
            width: 500,
            height: 440,
            child: ListView(
              children: [
                const Text('حدد الاختصارات ورتبها بالسهمين.'),
                const SizedBox(height: 10),
                for (final item in available)
                  Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(item.title),
                          secondary: Icon(item.icon),
                          value: order.contains(item.id),
                          onChanged: (checked) {
                            updateDialog(() {
                              if (checked == true) {
                                if (!order.contains(item.id)) {
                                  order.add(item.id);
                                }
                              } else if (order.length > 1) {
                                order.remove(item.id);
                              }
                            });
                          },
                        ),
                      ),
                      if (order.contains(item.id)) ...[
                        IconButton(
                          tooltip: 'للأعلى: ${item.title}',
                          onPressed: order.indexOf(item.id) == 0
                              ? null
                              : () => updateDialog(() {
                                    final index = order.indexOf(item.id);
                                    order.removeAt(index);
                                    order.insert(index - 1, item.id);
                                  }),
                          icon: const Icon(Icons.arrow_upward, size: 18),
                        ),
                        IconButton(
                          tooltip: 'للأسفل: ${item.title}',
                          onPressed: order.indexOf(item.id) == order.length - 1
                              ? null
                              : () => updateDialog(() {
                                    final index = order.indexOf(item.id);
                                    order.removeAt(index);
                                    order.insert(index + 1, item.id);
                                  }),
                          icon: const Icon(Icons.arrow_downward, size: 18),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: order.isEmpty
                  ? null
                  : () => Navigator.of(dialogContext).pop(order),
              child: const Text('حفظ الاختصارات'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null || preferenceKey != _preferenceKey) {
      return;
    }
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setStringList(preferenceKey, selected);
      if (!saved) {
        throw StateError('Unable to save shortcuts');
      }
      if (mounted && preferenceKey == _preferenceKey) {
        setState(() => _visibleIds = selected);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر حفظ اختصارات لوحة التحكم.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final byId = {for (final item in _available) item.id: item};
    final shortcuts = [
      for (final id in _visibleIds)
        if (byId.containsKey(id)) byId[id]!,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'اختصارات العمل',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            TextButton.icon(
              onPressed: _saving ? null : _customize,
              icon: const Icon(Icons.tune_outlined),
              label: const Text('تخصيص'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = width >= 1000
                ? 6
                : width >= 650
                    ? 4
                    : width >= 400
                        ? 3
                        : 2;
            final itemWidth = (width - (columns - 1) * 10) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final item in shortcuts)
                  SizedBox(
                    width: itemWidth,
                    height: 122,
                    child: _ShortcutCard(
                      key: ValueKey('shortcut-${item.id}'),
                      item: item,
                      onTap: () => widget.onOpenModule(item.id),
                      onLongPress: _customize,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _DashboardShortcut {
  const _DashboardShortcut(this.id, this.title, this.icon);

  final String id;
  final String title;
  final IconData icon;
}

class _ShortcutCard extends StatefulWidget {
  const _ShortcutCard({
    required this.item,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  final _DashboardShortcut item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_ShortcutCard> createState() => _ShortcutCardState();
}

class _ShortcutCardState extends State<_ShortcutCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final primary = colors.primary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: primary.withValues(
                  alpha: _pressed
                      ? 0.45
                      : _hovered
                          ? 0.3
                          : 0.1),
              width: _pressed
                  ? 2
                  : _hovered
                      ? 1.5
                      : 1,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : const [],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              onHighlightChanged: (value) {
                if (mounted) setState(() => _pressed = value);
              },
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            primary,
                            primary.withValues(alpha: 0.75),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        widget.item.icon,
                        size: 26,
                        color: colors.onPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.item.title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
