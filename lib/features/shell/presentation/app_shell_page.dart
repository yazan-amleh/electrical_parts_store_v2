import 'package:flutter/material.dart';

import '../../../app/app_dependencies.dart';
import '../../dashboard/presentation/dashboard_page.dart';
import '../../categories/domain/repositories/category_repository.dart';
import '../../categories/presentation/categories_page.dart';
import '../../accounting/domain/repositories/accounting_query_repository.dart';
import '../../accounting/domain/repositories/accounting_repository.dart';
import '../../accounting/presentation/financial_statements_page.dart';
import '../../accounting/presentation/ledger_page.dart';
import '../../accounting/presentation/manual_journal_page.dart';
import '../../accounting/presentation/chart_of_accounts_page.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../../auth/domain/enums/store_role.dart';
import '../../parties/domain/enums/party_type.dart';
import '../../parties/domain/repositories/party_repository.dart';
import '../../parties/presentation/party_directory_page.dart';
import '../../inventory/domain/repositories/product_repository.dart';
import '../../inventory/presentation/products_page.dart';
import '../../inventory/domain/repositories/inventory_repository.dart';
import '../../inventory/presentation/inventory_movements_page.dart';
import '../../sales/domain/repositories/sale_repository.dart';
import '../../sales/presentation/sales_page.dart';
import '../../purchases/domain/repositories/purchase_repository.dart';
import '../../purchases/presentation/purchases_page.dart';
import '../../offers/domain/repositories/offer_repository.dart';
import '../../offers/presentation/offers_page.dart';
import '../../purchase_orders/domain/repositories/purchase_order_repository.dart';
import '../../purchase_orders/presentation/purchase_orders_page.dart';
import '../../expenses/domain/repositories/expense_repository.dart';
import '../../expenses/presentation/expenses_page.dart';
import '../../payments/domain/repositories/party_payment_repository.dart';
import '../../transfers/domain/repositories/account_transfer_repository.dart';
import '../../transfers/presentation/account_transfers_page.dart';

class AppShellPage extends StatefulWidget {
  const AppShellPage({
    required this.dependencies,
    required this.user,
    required this.membership,
    required this.onSignOut,
    super.key,
  });

  final AppDependencies dependencies;
  final AuthenticatedUser user;
  final StoreMembership membership;
  final Future<void> Function() onSignOut;

  @override
  State<AppShellPage> createState() => _AppShellPageState();
}

class _AppShellPageState extends State<AppShellPage> {
  static const _sections = <_NavigationSection>[
    _NavigationSection(
      title: 'عام',
      modules: [
        _Module(
          id: 'dashboard',
          label: 'لوحة التحكم',
          icon: Icons.dashboard_outlined,
          description: 'ملخص المبيعات والمشتريات والمخزون والسيولة.',
          capabilities: ['ملخص اليوم', 'تنبيهات التشغيل', 'اختصارات العمل'],
          foundationReady: true,
        ),
      ],
    ),
    _NavigationSection(
      title: 'المبيعات',
      modules: [
        _Module(
          id: 'sales',
          label: 'المبيعات ونقطة البيع',
          icon: Icons.point_of_sale_outlined,
          description: 'إنشاء المبيعات وترحيلها بقيود متوازنة.',
          capabilities: ['بيع نقدي', 'بيع آجل', 'خصومات وضريبة'],
          foundationReady: true,
        ),
        _Module(
          id: 'sales-reports',
          label: 'تقارير وتحليلات المبيعات',
          icon: Icons.trending_up_outlined,
          description: 'تقارير المبيعات والتفصيل حسب الفترة والمستخدم.',
          capabilities: ['تقارير الفترة', 'تحليل الأصناف', 'تصدير'],
          foundationReady: false,
        ),
        _Module(
          id: 'offers',
          label: 'العروض والطلبات',
          icon: Icons.request_quote_outlined,
          description: 'العروض والطلبات قبل تحويلها إلى مستندات مرحّلة.',
          capabilities: ['مسودة', 'تحويل إلى بيع', 'تتبع الحالة'],
          foundationReady: true,
        ),
      ],
    ),
    _NavigationSection(
      title: 'المشتريات',
      modules: [
        _Module(
          id: 'purchases',
          label: 'المشتريات',
          icon: Icons.shopping_cart_outlined,
          description: 'تسجيل المشتريات وتحديث المخزون والدائنين ذرياً.',
          capabilities: ['شراء نقدي', 'شراء آجل', 'ضريبة مدخلات'],
          foundationReady: true,
        ),
        _Module(
          id: 'purchase-orders',
          label: 'طلبات الشراء',
          icon: Icons.playlist_add_check_outlined,
          description: 'إدارة طلبات الشراء قبل اعتماد الفاتورة.',
          capabilities: ['إنشاء طلب', 'اعتماد', 'تحويل إلى شراء'],
          foundationReady: true,
        ),
      ],
    ),
    _NavigationSection(
      title: 'المخزون',
      modules: [
        _Module(
          id: 'products',
          label: 'الأصناف والخدمات',
          icon: Icons.inventory_2_outlined,
          description: 'الأصناف والوحدات والأسعار والتكلفة.',
          capabilities: ['أصناف', 'خدمات', 'باركود ووحدات'],
          foundationReady: true,
        ),
        _Module(
          id: 'inventory',
          label: 'حركات وأرصدة المخزون',
          icon: Icons.swap_vert_outlined,
          description: 'تتبع الحركة والقيمة والكميات دون تعديل مباشر للرصيد.',
          capabilities: ['حركة وارد', 'حركة صادر', 'حد الطلب'],
          foundationReady: true,
        ),
        _Module(
          id: 'categories',
          label: 'التصنيفات',
          icon: Icons.category_outlined,
          description: 'تنظيم الأصناف ضمن شجرة تصنيفات قابلة للتوسع.',
          capabilities: ['تصنيفات', 'بحث', 'فلترة'],
          foundationReady: true,
        ),
      ],
    ),
    _NavigationSection(
      title: 'المحاسبة',
      modules: [
        _Module(
          id: 'chart-of-accounts',
          label: 'شجرة الحسابات',
          icon: Icons.account_tree_outlined,
          description: 'دليل حسابات واضح مع حسابات تحكم للعملاء والموردين.',
          capabilities: ['شجرة', 'حسابات رئيسية', 'حسابات فرعية'],
          foundationReady: true,
        ),
        _Module(
          id: 'journal',
          label: 'القيود اليومية',
          icon: Icons.menu_book_outlined,
          description: 'قيود متوازنة مع مفتاح تكرار ومصدر واضح.',
          capabilities: ['قيد يدوي', 'ترحيل', 'عكس'],
          foundationReady: true,
        ),
        _Module(
          id: 'ledger',
          label: 'دفتر الأستاذ وكشوف الحساب',
          icon: Icons.book_outlined,
          description:
              'الحركة والرصيد من القيود المرحّلة والإسقاطات القابلة لإعادة البناء.',
          capabilities: ['دفتر أستاذ', 'كشف عميل', 'كشف مورد'],
          foundationReady: true,
        ),
        _Module(
          id: 'financial-statements',
          label: 'القوائم وميزان المراجعة',
          icon: Icons.assessment_outlined,
          description: 'ميزان المراجعة وقائمة الدخل والمركز المالي.',
          capabilities: ['ميزان مراجعة', 'دخل', 'مركز مالي'],
          foundationReady: false,
        ),
        _Module(
          id: 'expenses',
          label: 'المصروفات والضرائب',
          icon: Icons.receipt_long_outlined,
          description: 'مصروفات نقدية أو آجلة مع ضريبة المدخلات.',
          capabilities: ['مصروف', 'ضريبة', 'مورد'],
          foundationReady: true,
        ),
      ],
    ),
    _NavigationSection(
      title: 'الصناديق والبنوك',
      modules: [
        _Module(
          id: 'cash-banks',
          label: 'الصناديق والبنوك',
          icon: Icons.account_balance_wallet_outlined,
          description: 'السيولة والحسابات البنكية والتحويلات الداخلية.',
          capabilities: ['صندوق', 'بنك', 'تحويل داخلي'],
          foundationReady: true,
        ),
        _Module(
          id: 'checks',
          label: 'الشيكات',
          icon: Icons.payments_outlined,
          description: 'تسجيل الشيكات ومتابعة حالتها ضمن دورة التحصيل.',
          capabilities: ['وارد', 'صادر', 'استحقاق'],
          foundationReady: false,
        ),
      ],
    ),
    _NavigationSection(
      title: 'العملاء والموردون',
      modules: [
        _Module(
          id: 'customers',
          label: 'العملاء',
          icon: Icons.people_outline,
          description: 'بيانات العملاء وأرصدتهم وكشوف حساباتهم.',
          capabilities: ['بيانات', 'كشف حساب', 'تحصيل'],
          foundationReady: true,
        ),
        _Module(
          id: 'suppliers',
          label: 'الموردون',
          icon: Icons.local_shipping_outlined,
          description: 'بيانات الموردين والالتزامات والمدفوعات.',
          capabilities: ['بيانات', 'كشف حساب', 'دفع'],
          foundationReady: true,
        ),
      ],
    ),
    _NavigationSection(
      title: 'التشغيل والتقارير',
      modules: [
        _Module(
          id: 'repairs',
          label: 'الصيانة والإصلاحات',
          icon: Icons.build_outlined,
          description: 'تتبع طلبات الإصلاح وحالتها وتكاليفها.',
          capabilities: ['استلام', 'حالة', 'تسليم'],
          foundationReady: false,
        ),
        _Module(
          id: 'reports',
          label: 'التقارير والتصدير',
          icon: Icons.analytics_outlined,
          description: 'مركز تقارير موحد مع تصدير ومرشحات.',
          capabilities: ['تقارير', 'تصدير', 'طباعة'],
          foundationReady: false,
        ),
        _Module(
          id: 'chat',
          label: 'المحادثات والإشعارات',
          icon: Icons.chat_outlined,
          description: 'التواصل والتنبيهات المرتبطة بالعمل.',
          capabilities: ['محادثة', 'إشعارات', 'نشاط'],
          foundationReady: false,
        ),
      ],
    ),
    _NavigationSection(
      title: 'الإدارة',
      modules: [
        _Module(
          id: 'settings',
          label: 'الإعدادات',
          icon: Icons.settings_outlined,
          description: 'إعدادات المتجر والمستخدمين والأدوار والتفضيلات.',
          capabilities: ['المتجر', 'المستخدمون', 'الصلاحيات'],
          foundationReady: false,
        ),
      ],
    ),
  ];

  int selectedIndex = 0;

  List<_Module> get _modules => [
        for (final section in _sections) ...section.modules,
      ];

  @override
  Widget build(BuildContext context) {
    final modules = _modules;
    final selected = modules[selectedIndex];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(selected.label),
          actions: [
            Chip(
              avatar: const Icon(Icons.verified_user_outlined, size: 18),
              label: Text(widget.membership.role.arabicLabel),
            ),
            const SizedBox(width: 12),
          ],
        ),
        drawer: _buildDrawer(context),
        body: _ModuleLandingPage(
          module: selected,
          user: widget.user,
          productRepository: widget.dependencies.productRepository,
          categoryRepository: widget.dependencies.categoryRepository,
          inventoryRepository: widget.dependencies.inventoryRepository,
          saleRepository: widget.dependencies.saleRepository,
          purchaseRepository: widget.dependencies.purchaseRepository,
          purchaseOrderRepository: widget.dependencies.purchaseOrderRepository,
          offerRepository: widget.dependencies.offerRepository,
          expenseRepository: widget.dependencies.expenseRepository,
          accountingRepository: widget.dependencies.accountingRepository,
          partyPaymentRepository: widget.dependencies.partyPaymentRepository,
          partyRepository: widget.dependencies.partyRepository,
          accountTransferRepository:
              widget.dependencies.accountTransferRepository,
          accountingQueryRepository:
              widget.dependencies.accountingQueryRepository,
          membership: widget.membership,
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final navigationItems = <Widget>[];
    var moduleOffset = 0;

    for (final section in _sections) {
      final sectionOffset = moduleOffset;
      navigationItems.add(
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            20,
            12,
            20,
            4,
          ),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              section.title,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ),
      );

      for (var localIndex = 0;
          localIndex < section.modules.length;
          localIndex++) {
        navigationItems.add(
          ListTile(
            leading: Icon(section.modules[localIndex].icon),
            title: Text(section.modules[localIndex].label),
            selected: selectedIndex == sectionOffset + localIndex,
            onTap: () {
              setState(() {
                selectedIndex = sectionOffset + localIndex;
              });
              Navigator.of(context).pop();
            },
          ),
        );
      }
      moduleOffset += section.modules.length;
    }

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              accountName: Text(
                widget.user.displayName?.trim().isNotEmpty == true
                    ? widget.user.displayName!
                    : 'مستخدم V2',
              ),
              accountEmail: Text(widget.user.email),
              currentAccountPicture: const CircleAvatar(
                child: Icon(Icons.person_outline),
              ),
              otherAccountsPictures: [
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    widget.membership.storeId,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: navigationItems,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('تسجيل الخروج'),
              onTap: () {
                Navigator.of(context).pop();
                widget.onSignOut();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ModuleLandingPage extends StatelessWidget {
  const _ModuleLandingPage({
    required this.module,
    required this.user,
    required this.productRepository,
    required this.categoryRepository,
    required this.inventoryRepository,
    required this.saleRepository,
    required this.purchaseRepository,
    required this.purchaseOrderRepository,
    required this.offerRepository,
    required this.expenseRepository,
    required this.accountingRepository,
    required this.partyPaymentRepository,
    required this.partyRepository,
    required this.accountTransferRepository,
    required this.accountingQueryRepository,
    required this.membership,
  });

  final _Module module;
  final AuthenticatedUser user;
  final ProductRepository? productRepository;
  final CategoryRepository? categoryRepository;
  final InventoryRepository? inventoryRepository;
  final SaleRepository? saleRepository;
  final PurchaseRepository? purchaseRepository;
  final PurchaseOrderRepository? purchaseOrderRepository;
  final OfferRepository? offerRepository;
  final ExpenseRepository? expenseRepository;
  final AccountingRepository? accountingRepository;
  final PartyPaymentRepository? partyPaymentRepository;
  final PartyRepository? partyRepository;
  final AccountTransferRepository? accountTransferRepository;
  final AccountingQueryRepository? accountingQueryRepository;
  final StoreMembership membership;

  @override
  Widget build(BuildContext context) {
    if (module.id == 'sales') {
      return SalesPage(
        repository: saleRepository,
        productRepository: productRepository,
        user: user,
        membership: membership,
      );
    }
    if (module.id == 'offers') {
      return OffersPage(
        repository: offerRepository,
        productRepository: productRepository,
        partyRepository: partyRepository,
        user: user,
        membership: membership,
      );
    }
    if (module.id == 'purchases') {
      return PurchasesPage(
        repository: purchaseRepository,
        productRepository: productRepository,
        user: user,
        membership: membership,
      );
    }
    if (module.id == 'purchase-orders') {
      return PurchaseOrdersPage(
        repository: purchaseOrderRepository,
        productRepository: productRepository,
        partyRepository: partyRepository,
        user: user,
        membership: membership,
      );
    }
    if (module.id == 'cash-banks') {
      return AccountTransfersPage(
        repository: accountTransferRepository,
        user: user,
        membership: membership,
      );
    }
    if (module.id == 'customers') {
      return PartyDirectoryPage(
        repository: partyRepository,
        paymentRepository: partyPaymentRepository,
        user: user,
        membership: membership,
        initialPartyType: PartyType.customer,
      );
    }
    if (module.id == 'suppliers') {
      return PartyDirectoryPage(
        repository: partyRepository,
        paymentRepository: partyPaymentRepository,
        user: user,
        membership: membership,
        initialPartyType: PartyType.supplier,
      );
    }
    if (module.id == 'expenses') {
      return ExpensesPage(
        repository: expenseRepository,
        user: user,
        membership: membership,
      );
    }
    if (module.id == 'categories') {
      return CategoriesPage(
        repository: categoryRepository,
        user: user,
        membership: membership,
      );
    }
    if (module.id == 'products') {
      return ProductsPage(
        repository: productRepository,
        categoryRepository: categoryRepository,
        user: user,
        membership: membership,
      );
    }
    if (module.id == 'inventory') {
      return InventoryMovementsPage(
        repository: inventoryRepository,
        productRepository: productRepository,
        user: user,
        membership: membership,
      );
    }
    if (module.id == 'chart-of-accounts') {
      return ChartOfAccountsPage(
        repository: accountingQueryRepository,
        user: user,
        membership: membership,
      );
    }
    if (module.id == 'journal') {
      return ManualJournalPage(
        repository: accountingRepository,
        queryRepository: accountingQueryRepository,
        user: user,
        membership: membership,
      );
    }
    if (module.id == 'ledger') {
      return LedgerPage(
        repository: accountingQueryRepository,
        user: user,
        membership: membership,
      );
    }
    if (module.id == 'financial-statements') {
      return FinancialStatementsPage(
        repository: accountingQueryRepository,
        user: user,
        membership: membership,
      );
    }
    if (module.id == 'dashboard') {
      return DashboardPage(
        accountingQueryRepository: accountingQueryRepository,
        productRepository: productRepository,
        user: user,
        membership: membership,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(module.icon, size: 56),
                  const SizedBox(height: 16),
                  Text(
                    module.label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    module.description,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final capability in module.capabilities)
                        Chip(label: Text(capability)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      module.foundationReady
                          ? 'محرك هذه الوحدة موجود في الأساس البرمجي، '
                              'والخطوة التالية تركيب واجهتها وربطها بحالات '
                              'التحميل والأخطاء والصلاحيات.'
                          : 'هذه الوحدة مثبتة في خريطة الترحيل حتى لا تضيع '
                              'أي ميزة من V1، وسيتم تنفيذها ضمن ترتيب الترحيل.',
                      textAlign: TextAlign.center,
                    ),
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

class _NavigationSection {
  const _NavigationSection({
    required this.title,
    required this.modules,
  });

  final String title;
  final List<_Module> modules;
}

class _Module {
  const _Module({
    required this.id,
    required this.label,
    required this.icon,
    required this.description,
    required this.capabilities,
    required this.foundationReady,
  });

  final String id;
  final String label;
  final IconData icon;
  final String description;
  final List<String> capabilities;
  final bool foundationReady;
}

extension on StoreRole {
  String get arabicLabel {
    switch (this) {
      case StoreRole.owner:
        return 'مالك';
      case StoreRole.admin:
        return 'مدير';
      case StoreRole.accountant:
        return 'محاسب';
      case StoreRole.sales:
        return 'مبيعات';
      case StoreRole.warehouse:
        return 'مستودع';
      case StoreRole.viewer:
        return 'مشاهد';
    }
  }
}
