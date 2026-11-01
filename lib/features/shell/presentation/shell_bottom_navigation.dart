import 'package:flutter/material.dart';

import '../../auth/domain/enums/store_role.dart';

/// Compact navigation inspired by V1's bottom tabs.
///
/// The vouchers hub has not yet been fully ported; V2's party-payments screen
/// is an interim, explicitly named destination rather than a parity claim.
class ShellBottomNavigation extends StatelessWidget {
  const ShellBottomNavigation({
    required this.activeModuleId,
    required this.role,
    required this.onOpenModule,
    required this.onMore,
    this.tabIds,
    super.key,
  });

  final String activeModuleId;
  final StoreRole role;
  final ValueChanged<String> onOpenModule;
  final VoidCallback onMore;
  final List<String>? tabIds;

  static List<ShellTabOption> optionsForRole(StoreRole role) => [
        const ShellTabOption(
          'dashboard',
          'الرئيسية',
          Icons.dashboard_outlined,
        ),
        if (role.canManageSales)
          const ShellTabOption('sales', 'المبيعات', Icons.point_of_sale),
        if (role.canPostAccounting) ...[
          const ShellTabOption(
            'vouchers-hub',
            'السندات',
            Icons.receipt_long_outlined,
          ),
          const ShellTabOption(
            'party-payments',
            'القبض والدفع',
            Icons.payments_outlined,
          ),
        ],
        const ShellTabOption('customers', 'العملاء', Icons.people_outline),
        if (role.canManageInventory) ...[
          const ShellTabOption(
            'purchases',
            'المشتريات',
            Icons.shopping_cart_outlined,
          ),
          const ShellTabOption(
            'products',
            'الأصناف',
            Icons.inventory_2_outlined,
          ),
          const ShellTabOption(
            'inventory',
            'المخزون',
            Icons.inventory_outlined,
          ),
        ],
        const ShellTabOption('notes', 'الملاحظات', Icons.note_alt_outlined),
      ];

  @override
  Widget build(BuildContext context) {
    final available = {
      for (final option in optionsForRole(role)) option.id: option,
    };
    final requested =
        tabIds ?? const ['dashboard', 'sales', 'vouchers-hub', 'customers'];
    final displayedIds = <String>[];
    for (final id in requested) {
      if (available.containsKey(id) && !displayedIds.contains(id)) {
        displayedIds.add(id);
      }
      if (displayedIds.length == 4) break;
    }
    if (displayedIds.isEmpty) displayedIds.add('dashboard');
    final destinations = [
      for (final id in displayedIds) available[id]!,
      const ShellTabOption('more', 'المزيد', Icons.menu),
    ];

    final selectedIndex = destinations.indexWhere(
      (item) => item.id == activeModuleId,
    );
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.primary, colors.primary.withValues(alpha: 0.86)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: BottomNavigationBar(
        key: const ValueKey('shell-bottom-navigation'),
        items: [
          for (final item in destinations)
            BottomNavigationBarItem(
              icon: Icon(item.icon),
              label: item.title,
            ),
        ],
        currentIndex:
            selectedIndex < 0 ? destinations.length - 1 : selectedIndex,
        onTap: (index) {
          final id = destinations[index].id;
          if (id == 'more') {
            onMore();
          } else {
            onOpenModule(id);
          }
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white70,
        showUnselectedLabels: true,
        selectedFontSize: 12,
        unselectedFontSize: 11,
      ),
    );
  }
}

class ShellTabOption {
  const ShellTabOption(this.id, this.title, this.icon);

  final String id;
  final String title;
  final IconData icon;
}
