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
    super.key,
  });

  final String activeModuleId;
  final StoreRole role;
  final ValueChanged<String> onOpenModule;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final destinations = <_BottomDestination>[
      const _BottomDestination(
        'dashboard',
        'الرئيسية',
        Icons.dashboard_outlined,
      ),
      if (role.canManageSales)
        const _BottomDestination('sales', 'المبيعات', Icons.point_of_sale),
      if (role.canManageSales || role.canPostAccounting)
        const _BottomDestination(
          'party-payments',
          'القبض والدفع',
          Icons.payments_outlined,
        ),
      const _BottomDestination(
        'customers',
        'العملاء',
        Icons.people_outline,
      ),
      const _BottomDestination('more', 'المزيد', Icons.menu),
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

class _BottomDestination {
  const _BottomDestination(this.id, this.title, this.icon);

  final String id;
  final String title;
  final IconData icon;
}
