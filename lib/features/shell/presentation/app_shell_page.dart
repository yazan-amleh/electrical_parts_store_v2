import 'package:flutter/material.dart';

class AppShellPage extends StatefulWidget {
  const AppShellPage({super.key});

  @override
  State<AppShellPage> createState() => _AppShellPageState();
}

class _AppShellPageState extends State<AppShellPage> {
  static const modules = <_Module>[
    _Module('الرئيسية', Icons.dashboard_outlined),
    _Module('المبيعات', Icons.point_of_sale_outlined),
    _Module('المشتريات', Icons.shopping_cart_outlined),
    _Module('المخزون', Icons.inventory_2_outlined),
    _Module('المحاسبة', Icons.account_balance_outlined),
    _Module('الصناديق والبنوك', Icons.account_balance_wallet_outlined),
    _Module('التقارير', Icons.analytics_outlined),
    _Module('الإعدادات', Icons.settings_outlined),
  ];

  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final selected = modules[selectedIndex];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(selected.label),
          actions: const [
            Padding(
              padding: EdgeInsetsDirectional.only(end: 16),
              child: Center(child: Text('V2')),
            ),
          ],
        ),
        drawer: Drawer(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                const ListTile(
                  title: Text(
                    'منصة المتجر والمحاسبة',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('النسخة الجديدة'),
                ),
                const Divider(),
                for (var index = 0; index < modules.length; index++)
                  ListTile(
                    leading: Icon(modules[index].icon),
                    title: Text(modules[index].label),
                    selected: selectedIndex == index,
                    onTap: () {
                      setState(() => selectedIndex = index);
                      Navigator.of(context).pop();
                    },
                  ),
              ],
            ),
          ),
        ),
        body: Center(
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(selected.icon, size: 52),
                  const SizedBox(height: 16),
                  Text(
                    selected.label,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'الأساس البرمجي جاهز. سيتم تركيب شاشات ومزايا V1 كاملة داخل حدود V2 الجديدة.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Module {
  const _Module(this.label, this.icon);

  final String label;
  final IconData icon;
}
