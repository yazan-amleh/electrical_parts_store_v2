import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/app_dependencies.dart';
import 'shell_bottom_navigation.dart';
import '../../../core/tenancy/store_context.dart';
import '../../../core/result/result.dart';
import '../../dashboard/presentation/dashboard_page.dart';
import '../../categories/domain/repositories/category_repository.dart';
import '../../categories/domain/services/category_inventory_document_builder.dart';
import '../../categories/presentation/categories_page.dart';
import '../../accounting/domain/repositories/accounting_query_repository.dart';
import '../../accounting/data/repositories/firestore_chart_mutation_repository.dart';
import '../../accounting/domain/repositories/accounting_repository.dart';
import '../../accounting/presentation/financial_statements_page.dart';
import '../../accounting_audit/domain/repositories/accounting_audit_repository.dart';
import '../../accounting_audit/data/repositories/firestore_accounting_close_repository.dart';
import '../../accounting_audit/presentation/accounting_audit_page.dart';
import '../../activity_log/domain/repositories/activity_log_repository.dart';
import '../../activity_log/presentation/activity_log_page.dart';
import '../../accounting/presentation/ledger_page.dart';
import '../../accounting/presentation/manual_journal_page.dart';
import '../../accounting/presentation/chart_of_accounts_page.dart';
import '../../accounting/presentation/trial_balance_page.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../../auth/domain/enums/store_role.dart';
import '../../parties/domain/enums/party_type.dart';
import '../../parties/domain/repositories/party_ledger_repository.dart';
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
import '../../payments/domain/repositories/voucher_query_repository.dart';
import '../../payments/presentation/party_payments_page.dart';
import '../../payments/presentation/vouchers_hub_page.dart';
import '../../cheques/domain/repositories/cheque_repository.dart';
import '../../cheques/presentation/cheques_page.dart';
import '../../transfers/domain/repositories/account_transfer_repository.dart';
import '../../transfers/presentation/cash_banks_page.dart';
import '../../repairs/domain/repositories/repair_repository.dart';
import '../../repairs/domain/services/repair_document_builder.dart';
import '../../repairs/presentation/repairs_page.dart';
import '../../reports/domain/repositories/reports_repository.dart';
import '../../reports/domain/services/report_document_builder.dart';
import '../../reports/presentation/reports_page.dart';
import '../../reports/presentation/sales_analytics_page.dart';
import '../../chat/domain/repositories/chat_attachment_repository.dart';
import '../../chat/domain/repositories/chat_repository.dart';
import '../../chat/presentation/chat_page.dart';
import '../../chatbot/presentation/chatbot_page.dart';
import '../../settings/domain/repositories/settings_repository.dart';
import '../../settings/domain/entities/store_profile.dart';
import '../../notes/domain/repositories/note_repository.dart';
import '../../notes/presentation/notes_page.dart';
import '../../settings/presentation/settings_page.dart';

class AppShellPage extends StatefulWidget {
  const AppShellPage({
    required this.dependencies,
    required this.user,
    required this.membership,
    required this.onSignOut,
    required this.onChooseStore,
    super.key,
  });

  final AppDependencies dependencies;
  final AuthenticatedUser user;
  final StoreMembership membership;
  final Future<void> Function() onSignOut;
  final VoidCallback onChooseStore;

  @override
  State<AppShellPage> createState() => _AppShellPageState();
}

class _AppShellPageState extends State<AppShellPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  List<String>? _bottomNavIds;
  bool _savingBottomNavigation = false;
  int _bottomNavEpoch = 0;
  int _storeProfileEpoch = 0;
  String? _storeDisplayName;

  String get _bottomNavPreferenceKey =>
      'v2:bottom-navigation:${widget.membership.storeId}:${widget.user.id}';
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
          foundationReady: true,
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
          id: 'trial-balance',
          label: 'ميزان المراجعة',
          icon: Icons.table_chart_outlined,
          description: 'عرض أرصدة المدين والدائن من القيود المرحّلة.',
          capabilities: ['مدين', 'دائن', 'فحص التوازن'],
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
          foundationReady: true,
        ),
        _Module(
          id: 'accounting-audit',
          label: 'فحص سلامة المحاسبة',
          icon: Icons.fact_check_outlined,
          description: 'مطابقة القيود مع الأرصدة وكشوف الأطراف والمخزون.',
          capabilities: ['مطابقة القيود', 'فحص الأرصدة', 'كشف الفروقات'],
          foundationReady: true,
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
          capabilities: ['شيكات واردة', 'شيكات صادرة', 'تحصيل', 'ارتجاع'],
          foundationReady: true,
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
        _Module(
          id: 'vouchers-hub',
          label: 'مركز السندات المالية',
          icon: Icons.receipt_long_outlined,
          description: 'تبويبات القبض والدفع وعرض أحداث الحركات المسجلة.',
          capabilities: ['قبض من عميل', 'دفع لمورد', 'آخر أحداث الدفع'],
          foundationReady: true,
        ),
        _Module(
          id: 'party-payments',
          label: 'القبض والدفع',
          icon: Icons.payments_outlined,
          description: 'تسجيل قبض العملاء ودفع الموردين ضمن قيد متوازن.',
          capabilities: ['قبض من عميل', 'دفع لمورد', 'نقدي وبنكي وشيكات'],
          foundationReady: true,
        ),
      ],
    ),
    _NavigationSection(
      title: 'المتابعة والأدوات',
      modules: [
        _Module(
          id: 'notes',
          label: 'الملاحظات',
          icon: Icons.notes_outlined,
          description: 'ملاحظات شخصية ومهام وتذكيرات مرتبطة بالعمل.',
          capabilities: ['بحث', 'أولوية', 'أرشفة وتمييز'],
          foundationReady: true,
        ),
        _Module(
          id: 'activity-log',
          label: 'سجل النشاط',
          icon: Icons.history_outlined,
          description: 'قراءة الأحداث التشغيلية المرتبطة بالمتجر.',
          capabilities: ['تغذية زمنية', 'المستخدم', 'نوع الحدث'],
          foundationReady: true,
        ),
        _Module(
          id: 'chatbot',
          label: 'المساعد الذكي',
          icon: Icons.auto_awesome_outlined,
          description: 'إجابات سريعة عن المبيعات والمخزون والتصنيفات.',
          capabilities: ['مبيعات', 'مخزون', 'تصنيفات'],
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
          capabilities: [
            'استلام جهاز',
            'فحص وتشخيص',
            'قطع مستخدمة',
            'دفعة مقدمة',
            'فاتورة وتسليم',
            'متابعة الحالة',
          ],
          foundationReady: true,
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
          foundationReady: true,
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
  void initState() {
    super.initState();
    _loadBottomNavigation();
    _loadStoreProfile();
    _registerNotifications();
  }

  @override
  void didUpdateWidget(covariant AppShellPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.user.id != oldWidget.user.id ||
        widget.membership.storeId != oldWidget.membership.storeId ||
        widget.membership.role != oldWidget.membership.role) {
      _loadBottomNavigation();
      _loadStoreProfile();
    }
  }

  Future<void> _loadStoreProfile() async {
    final epoch = ++_storeProfileEpoch;
    final repository = widget.dependencies.settingsRepository;
    if (repository == null) {
      if (mounted) setState(() => _storeDisplayName = null);
      return;
    }

    if (mounted) setState(() => _storeDisplayName = null);
    try {
      final result = await repository.getStoreProfile(
        context: StoreContext(
          storeId: widget.membership.storeId,
          userId: widget.user.id,
        ),
      );
      if (!mounted || epoch != _storeProfileEpoch) return;
      if (result is Success<StoreProfile>) {
        setState(() => _storeDisplayName = result.value.name.trim());
      }
    } catch (_) {
      // Store ID remains a reliable title if the profile cannot be read.
    }
  }

  Future<void> _loadBottomNavigation() async {
    final epoch = ++_bottomNavEpoch;
    final key = _bottomNavPreferenceKey;
    List<String>? saved;
    try {
      final preferences = await SharedPreferences.getInstance();
      saved = preferences.getStringList(key);
    } catch (_) {
      // A missing local preference should never block store navigation.
    }
    if (!mounted || epoch != _bottomNavEpoch) return;
    setState(() => _bottomNavIds = saved);
  }

  Future<void> _customizeBottomNavigation() async {
    if (_savingBottomNavigation) return;
    final key = _bottomNavPreferenceKey;
    final options = ShellBottomNavigation.optionsForRole(
      widget.membership.role,
    );
    final allowedIds = options.map((item) => item.id).toSet();
    final order = [
      for (final id in _bottomNavIds ??
          const ['dashboard', 'sales', 'vouchers-hub', 'customers'])
        if (allowedIds.contains(id)) id,
    ];
    if (order.isEmpty) order.add('dashboard');

    final chosen = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, updateDialog) => AlertDialog(
          title: const Text('تخصيص الشريط السفلي'),
          content: SizedBox(
            width: 490,
            height: 390,
            child: ListView(
              children: [
                const Text('اختر حتى أربع وحدات، ورتبها بالسهمين.'),
                const SizedBox(height: 8),
                for (final option in options)
                  Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(option.title),
                          secondary: Icon(option.icon),
                          value: order.contains(option.id),
                          onChanged: (checked) {
                            updateDialog(() {
                              if (checked == true &&
                                  order.length < 4 &&
                                  !order.contains(option.id)) {
                                order.add(option.id);
                              } else if (checked == false && order.length > 1) {
                                order.remove(option.id);
                              }
                            });
                          },
                        ),
                      ),
                      if (order.contains(option.id)) ...[
                        IconButton(
                          tooltip: 'للأعلى: ${option.title}',
                          onPressed: order.indexOf(option.id) == 0
                              ? null
                              : () => updateDialog(() {
                                    final index = order.indexOf(option.id);
                                    order.removeAt(index);
                                    order.insert(index - 1, option.id);
                                  }),
                          icon: const Icon(Icons.arrow_upward, size: 18),
                        ),
                        IconButton(
                          tooltip: 'للأسفل: ${option.title}',
                          onPressed:
                              order.indexOf(option.id) == order.length - 1
                                  ? null
                                  : () => updateDialog(() {
                                        final index = order.indexOf(option.id);
                                        order.removeAt(index);
                                        order.insert(index + 1, option.id);
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
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || chosen == null || key != _bottomNavPreferenceKey) {
      return;
    }
    setState(() => _savingBottomNavigation = true);
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!await preferences.setStringList(key, chosen)) {
        throw StateError('Could not save navigation preference');
      }
      if (mounted && key == _bottomNavPreferenceKey) {
        setState(() => _bottomNavIds = chosen);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر حفظ إعدادات التنقل.')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingBottomNavigation = false);
    }
  }

  Future<void> _registerNotifications() async {
    final repository = widget.dependencies.notificationRepository;
    if (repository == null) {
      return;
    }
    await repository.registerCurrentDevice(
      context: StoreContext(
        storeId: widget.membership.storeId,
        userId: widget.user.id,
      ),
    );
  }

  Future<void> _unregisterNotifications() async {
    final repository = widget.dependencies.notificationRepository;
    if (repository != null) {
      await repository.unregisterCurrentDevice(
        context: StoreContext(
          storeId: widget.membership.storeId,
          userId: widget.user.id,
        ),
      );
    }
  }

  void _openModule(String moduleId) {
    final index = _modules.indexWhere((module) => module.id == moduleId);
    if (index < 0) return;
    final previousId = _modules[selectedIndex].id;
    setState(() => selectedIndex = index);
    if (previousId == 'settings') _loadStoreProfile();
  }

  Future<void> _searchModules() async {
    var filter = '';
    final modules = _modules;
    final chosen = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, updateDialog) {
          final matches = [
            for (var i = 0; i < modules.length; i++)
              if (modules[i].label.contains(filter) ||
                  modules[i].description.contains(filter))
                i,
          ];
          return AlertDialog(
            title: const Text('الانتقال إلى وحدة'),
            content: SizedBox(
              width: 480,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    textDirection: TextDirection.rtl,
                    decoration: const InputDecoration(
                      hintText: 'ابحث عن الوحدة',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) =>
                        updateDialog(() => filter = value.trim()),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: matches.isEmpty
                        ? const Center(child: Text('لا توجد نتائج مطابقة'))
                        : ListView.builder(
                            itemCount: matches.length,
                            itemBuilder: (context, index) {
                              final moduleIndex = matches[index];
                              final module = modules[moduleIndex];
                              return ListTile(
                                leading: Icon(module.icon),
                                title: Text(module.label),
                                onTap: () => Navigator.of(dialogContext)
                                    .pop(moduleIndex),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('إغلاق'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || chosen == null) return;
    _openModule(modules[chosen].id);
  }

  Future<void> _signOut() async {
    await _unregisterNotifications();
    await widget.onSignOut();
  }

  Future<void> _chooseStore() async {
    await _unregisterNotifications();
    widget.onChooseStore();
  }

  @override
  Widget build(BuildContext context) {
    final modules = _modules;
    final selected = modules[selectedIndex];
    final showCompactNavigation = MediaQuery.sizeOf(context).width < 760;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          titleSpacing: 0,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          backgroundColor: Theme.of(context).colorScheme.primary,
          flexibleSpace: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.82),
                ],
              ),
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _storeDisplayName?.isNotEmpty == true
                    ? _storeDisplayName!
                    : widget.membership.storeId,
                key: const ValueKey('shell-store-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
              ),
              Text(
                selected.label,
                key: const ValueKey('shell-module-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onPrimary
                          .withValues(alpha: 0.85),
                    ),
              ),
            ],
          ),
          actions: [
            if (!showCompactNavigation)
              IconButton(
                tooltip: 'الرئيسية',
                onPressed: () => _openModule('dashboard'),
                icon: const Icon(Icons.home_outlined),
              ),
            if (!showCompactNavigation &&
                widget.dependencies.chatRepository != null)
              IconButton(
                tooltip: 'المحادثات',
                onPressed: () => _openModule('chat'),
                icon: const Icon(Icons.chat_bubble_outline),
              ),
            IconButton(
              tooltip: 'البحث في الوحدات',
              onPressed: _searchModules,
              icon: const Icon(Icons.search),
            ),
            if (!showCompactNavigation)
              Tooltip(
                message: 'دور المستخدم',
                child: Chip(
                  avatar: const Icon(Icons.verified_user_outlined, size: 18),
                  label: Text(widget.membership.role.arabicLabel),
                ),
              ),
            const SizedBox(width: 8),
          ],
        ),
        drawer: _buildDrawer(context),
        bottomNavigationBar: showCompactNavigation
            ? ShellBottomNavigation(
                activeModuleId: selected.id,
                role: widget.membership.role,
                tabIds: _bottomNavIds,
                onOpenModule: _openModule,
                onMore: () => _scaffoldKey.currentState?.openDrawer(),
              )
            : null,
        body: _ModuleLandingPage(
          module: selected,
          onOpenModule: _openModule,
          user: widget.user,
          productRepository: widget.dependencies.productRepository,
          categoryRepository: widget.dependencies.categoryRepository,
          categoryInventoryDocumentBuilder:
              widget.dependencies.categoryInventoryDocumentBuilder,
          inventoryRepository: widget.dependencies.inventoryRepository,
          saleRepository: widget.dependencies.saleRepository,
          purchaseRepository: widget.dependencies.purchaseRepository,
          purchaseOrderRepository: widget.dependencies.purchaseOrderRepository,
          offerRepository: widget.dependencies.offerRepository,
          expenseRepository: widget.dependencies.expenseRepository,
          accountingRepository: widget.dependencies.accountingRepository,
          accountingAuditRepository:
              widget.dependencies.accountingAuditRepository,
          accountingCloseRepository:
              widget.dependencies.accountingCloseRepository,
          partyPaymentRepository: widget.dependencies.partyPaymentRepository,
          voucherQueryRepository: widget.dependencies.voucherQueryRepository,
          chequeRepository: widget.dependencies.chequeRepository,
          partyRepository: widget.dependencies.partyRepository,
          partyLedgerRepository: widget.dependencies.partyLedgerRepository,
          accountTransferRepository:
              widget.dependencies.accountTransferRepository,
          accountingQueryRepository:
              widget.dependencies.accountingQueryRepository,
          chartMutationRepository: widget.dependencies.chartMutationRepository,
          repairRepository: widget.dependencies.repairRepository,
          repairDocumentBuilder: widget.dependencies.repairDocumentBuilder,
          reportsRepository: widget.dependencies.reportsRepository,
          reportDocumentBuilder: widget.dependencies.reportDocumentBuilder,
          chatRepository: widget.dependencies.chatRepository,
          chatAttachmentRepository:
              widget.dependencies.chatAttachmentRepository,
          settingsRepository: widget.dependencies.settingsRepository,
          noteRepository: widget.dependencies.noteRepository,
          activityLogRepository: widget.dependencies.activityLogRepository,
          membership: widget.membership,
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    var filter = '';
    return StatefulBuilder(
      builder: (drawerContext, updateDrawer) {
        final colorScheme = Theme.of(drawerContext).colorScheme;
        final query = filter.trim().toLowerCase();
        final navigationItems = <Widget>[];

        for (final section in _sections) {
          final matchingModules = [
            for (final module in section.modules)
              if (query.isEmpty ||
                  module.label.toLowerCase().contains(query) ||
                  module.description.toLowerCase().contains(query))
                module,
          ];
          if (matchingModules.isEmpty) continue;

          navigationItems.add(
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 20, 4),
              child: Row(
                children: [
                  Container(
                    height: 16,
                    width: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    section.title,
                    style: Theme.of(drawerContext).textTheme.titleSmall,
                  ),
                ],
              ),
            ),
          );

          for (final module in matchingModules) {
            final moduleIndex =
                _modules.indexWhere((entry) => entry.id == module.id);
            final isSelected = moduleIndex == selectedIndex;
            navigationItems.add(
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                child: Material(
                  color: isSelected
                      ? colorScheme.primaryContainer
                      : colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    selected: isSelected,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        module.icon,
                        size: 22,
                        color: colorScheme.primary,
                      ),
                    ),
                    title: Text(module.label),
                    onTap: () {
                      Navigator.of(drawerContext).pop();
                      _openModule(module.id);
                    },
                  ),
                ),
              ),
            );
          }
        }

        return Drawer(
          child: SafeArea(
            child: Column(
              children: [
                UserAccountsDrawerHeader(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [
                        colorScheme.primary,
                        colorScheme.primary.withValues(alpha: 0.85),
                      ],
                    ),
                  ),
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
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    key: const ValueKey('shell-drawer-search'),
                    textDirection: TextDirection.rtl,
                    decoration: const InputDecoration(
                      hintText: 'ابحث في وحدات النظام',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => updateDrawer(() => filter = value),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: navigationItems.isEmpty
                      ? const Center(child: Text('لا توجد وحدات مطابقة'))
                      : ListView(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          children: navigationItems,
                        ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.tune_outlined),
                  title: const Text('تخصيص شريط التنقل'),
                  onTap: () {
                    Navigator.of(drawerContext).pop();
                    _customizeBottomNavigation();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: const Text('تغيير المتجر'),
                  onTap: () {
                    Navigator.of(drawerContext).pop();
                    _chooseStore();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('تسجيل الخروج'),
                  onTap: () {
                    Navigator.of(drawerContext).pop();
                    _signOut();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ModuleLandingPage extends StatelessWidget {
  const _ModuleLandingPage({
    required this.module,
    required this.onOpenModule,
    required this.user,
    required this.productRepository,
    required this.categoryRepository,
    required this.categoryInventoryDocumentBuilder,
    required this.inventoryRepository,
    required this.saleRepository,
    required this.purchaseRepository,
    required this.purchaseOrderRepository,
    required this.offerRepository,
    required this.expenseRepository,
    required this.accountingRepository,
    required this.accountingAuditRepository,
    this.accountingCloseRepository,
    required this.partyPaymentRepository,
    required this.voucherQueryRepository,
    required this.chequeRepository,
    required this.partyRepository,
    required this.partyLedgerRepository,
    required this.accountTransferRepository,
    required this.accountingQueryRepository,
    this.chartMutationRepository,
    required this.repairRepository,
    required this.repairDocumentBuilder,
    required this.reportsRepository,
    required this.reportDocumentBuilder,
    required this.chatRepository,
    this.chatAttachmentRepository,
    required this.settingsRepository,
    this.noteRepository,
    this.activityLogRepository,
    required this.membership,
  });

  final _Module module;
  final ValueChanged<String> onOpenModule;
  final AuthenticatedUser user;
  final ProductRepository? productRepository;
  final CategoryRepository? categoryRepository;
  final CategoryInventoryDocumentBuilder? categoryInventoryDocumentBuilder;
  final InventoryRepository? inventoryRepository;
  final SaleRepository? saleRepository;
  final PurchaseRepository? purchaseRepository;
  final PurchaseOrderRepository? purchaseOrderRepository;
  final OfferRepository? offerRepository;
  final ExpenseRepository? expenseRepository;
  final AccountingRepository? accountingRepository;
  final AccountingAuditRepository? accountingAuditRepository;
  final FirestoreAccountingCloseRepository? accountingCloseRepository;
  final PartyPaymentRepository? partyPaymentRepository;
  final VoucherQueryRepository? voucherQueryRepository;
  final ChequeRepository? chequeRepository;
  final PartyRepository? partyRepository;
  final PartyLedgerRepository? partyLedgerRepository;
  final AccountTransferRepository? accountTransferRepository;
  final AccountingQueryRepository? accountingQueryRepository;
  final FirestoreChartMutationRepository? chartMutationRepository;
  final RepairRepository? repairRepository;
  final RepairDocumentBuilder? repairDocumentBuilder;
  final ReportsRepository? reportsRepository;
  final ReportDocumentBuilder? reportDocumentBuilder;
  final ChatRepository? chatRepository;
  final ChatAttachmentRepository? chatAttachmentRepository;
  final SettingsRepository? settingsRepository;
  final NoteRepository? noteRepository;
  final ActivityLogRepository? activityLogRepository;
  final StoreMembership membership;

  @override
  Widget build(BuildContext context) {
    if (module.id == 'sales') {
      return SalesPage(
        repository: saleRepository,
        productRepository: productRepository,
        partyRepository: partyRepository,
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
        partyRepository: partyRepository,
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
      return CashBanksPage(
        accountingQueryRepository: accountingQueryRepository,
        transferRepository: accountTransferRepository,
        user: user,
        membership: membership,
      );
    }
    if (module.id == 'checks') {
      return ChequesPage(
        repository: chequeRepository,
        user: user,
        membership: membership,
      );
    }
    if (module.id == 'repairs') {
      return RepairsPage(
        repository: repairRepository,
        documentBuilder: repairDocumentBuilder,
        productRepository: productRepository,
        partyRepository: partyRepository,
        user: user,
        membership: membership,
      );
    }
    if (module.id == 'vouchers-hub') {
      return VouchersHubPage(
        paymentRepository: partyPaymentRepository,
        voucherQueryRepository: voucherQueryRepository,
        user: user,
        membership: membership,
      );
    }
    if (module.id == 'party-payments') {
      return PartyPaymentsPage(
        repository: partyPaymentRepository,
        user: user,
        membership: membership,
      );
    }
    if (module.id == 'customers') {
      return PartyDirectoryPage(
        repository: partyRepository,
        paymentRepository: partyPaymentRepository,
        ledgerRepository: partyLedgerRepository,
        user: user,
        membership: membership,
        initialPartyType: PartyType.customer,
      );
    }
    if (module.id == 'suppliers') {
      return PartyDirectoryPage(
        repository: partyRepository,
        paymentRepository: partyPaymentRepository,
        ledgerRepository: partyLedgerRepository,
        user: user,
        membership: membership,
        initialPartyType: PartyType.supplier,
      );
    }
    if (module.id == 'accounting-audit') {
      return AccountingAuditPage(
        repository: accountingAuditRepository,
        closeRepository: accountingCloseRepository,
        user: user,
        membership: membership,
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
        productRepository: productRepository,
        documentBuilder: categoryInventoryDocumentBuilder,
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
        mutationRepository: chartMutationRepository,
        user: user,
        membership: membership,
      );
    }
    if (module.id == 'trial-balance') {
      return TrialBalancePage(
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
    if (module.id == 'sales-reports') {
      return SalesAnalyticsPage(
        repository: reportsRepository,
        documentBuilder: reportDocumentBuilder,
        user: user,
        membership: membership,
      );
    }
    if (module.id == 'reports') {
      return ReportsPage(
        repository: reportsRepository,
        documentBuilder: reportDocumentBuilder,
        productRepository: productRepository,
        user: user,
        membership: membership,
      );
    }
    if (module.id == 'chat') {
      final chatRepository = this.chatRepository;
      final settingsRepository = this.settingsRepository;
      if (chatRepository != null && settingsRepository != null) {
        return ChatPage(
          repository: chatRepository,
          attachmentRepository: chatAttachmentRepository,
          settingsRepository: settingsRepository,
          user: user,
          membership: membership,
        );
      }
    }
    if (module.id == 'notes') {
      final noteRepository = this.noteRepository;
      if (noteRepository != null) {
        return NotesPage(
          repository: noteRepository,
          user: user,
          membership: membership,
        );
      }
    }
    if (module.id == 'activity-log') {
      final activityLogRepository = this.activityLogRepository;
      if (activityLogRepository != null) {
        return ActivityLogPage(
          repository: activityLogRepository,
          user: user,
          membership: membership,
        );
      }
    }
    if (module.id == 'chatbot') {
      final productRepository = this.productRepository;
      final categoryRepository = this.categoryRepository;
      final reportsRepository = this.reportsRepository;
      if (productRepository != null &&
          categoryRepository != null &&
          reportsRepository != null) {
        return ChatbotPage(
          productRepository: productRepository,
          categoryRepository: categoryRepository,
          reportsRepository: reportsRepository,
          user: user,
          membership: membership,
        );
      }
    }
    if (module.id == 'settings') {
      return SettingsPage(
        repository: settingsRepository,
        user: user,
        membership: membership,
      );
    }
    if (module.id == 'dashboard') {
      return DashboardPage(
        accountingQueryRepository: accountingQueryRepository,
        productRepository: productRepository,
        reportsRepository: reportsRepository,
        onOpenModule: onOpenModule,
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
                  Text(module.description, textAlign: TextAlign.center),
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
  const _NavigationSection({required this.title, required this.modules});

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
