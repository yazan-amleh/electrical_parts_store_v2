import '../entities/account.dart';
import '../enums/accounting_enums.dart';

abstract final class DefaultChartOfAccounts {
  static List<Account> forStore(String storeId) {
    if (storeId.trim().isEmpty) {
      throw ArgumentError('Store id is required.');
    }

    final accounts = <Account>[
      _header(
        storeId: storeId,
        id: '1100',
        code: '1100',
        name: 'الأصول المتداولة',
        section: StatementSection.currentAsset,
        sortOrder: 100,
      ),
      _posting(
        storeId: storeId,
        id: '1110',
        code: '1110',
        name: 'الصندوق الرئيسي',
        parentId: '1100',
        controlType: ControlType.cashBox,
        section: StatementSection.currentAsset,
        sortOrder: 110,
      ),
      _header(
        storeId: storeId,
        id: '1120',
        code: '1120',
        name: 'البنوك',
        section: StatementSection.currentAsset,
        sortOrder: 120,
      ),
      _posting(
        storeId: storeId,
        id: '1130',
        code: '1130',
        name: 'الشيكات قيد التحصيل',
        parentId: '1100',
        section: StatementSection.currentAsset,
        sortOrder: 130,
      ),
      _posting(
        storeId: storeId,
        id: '1140',
        code: '1140',
        name: 'ذمم العملاء',
        parentId: '1100',
        controlType: ControlType.customerReceivable,
        section: StatementSection.currentAsset,
        sortOrder: 140,
      ),
      _posting(
        storeId: storeId,
        id: '1150',
        code: '1150',
        name: 'المخزون',
        parentId: '1100',
        controlType: ControlType.inventory,
        section: StatementSection.currentAsset,
        sortOrder: 150,
      ),
      _posting(
        storeId: storeId,
        id: '1160',
        code: '1160',
        name: 'ذمم البطاقات',
        parentId: '1100',
        section: StatementSection.currentAsset,
        sortOrder: 160,
      ),
      _header(
        storeId: storeId,
        id: '1200',
        code: '1200',
        name: 'الأصول غير المتداولة',
        section: StatementSection.nonCurrentAsset,
        sortOrder: 200,
      ),
      _posting(
        storeId: storeId,
        id: '1210',
        code: '1210',
        name: 'المعدات والأثاث',
        parentId: '1200',
        controlType: ControlType.fixedAsset,
        section: StatementSection.nonCurrentAsset,
        sortOrder: 210,
      ),
      _header(
        storeId: storeId,
        id: '2100',
        code: '2100',
        name: 'الالتزامات المتداولة',
        section: StatementSection.currentLiability,
        normalSide: NormalSide.credit,
        sortOrder: 300,
      ),
      _posting(
        storeId: storeId,
        id: '2110',
        code: '2110',
        name: 'ذمم الموردين',
        parentId: '2100',
        controlType: ControlType.supplierPayable,
        section: StatementSection.currentLiability,
        normalSide: NormalSide.credit,
        sortOrder: 310,
      ),
      _posting(
        storeId: storeId,
        id: '2120',
        code: '2120',
        name: 'الضرائب المستحقة',
        parentId: '2100',
        controlType: ControlType.tax,
        section: StatementSection.currentLiability,
        normalSide: NormalSide.credit,
        sortOrder: 320,
      ),
      _header(
        storeId: storeId,
        id: '3100',
        code: '3100',
        name: 'حقوق الملكية',
        section: StatementSection.equity,
        normalSide: NormalSide.credit,
        sortOrder: 400,
      ),
      _posting(
        storeId: storeId,
        id: '3110',
        code: '3110',
        name: 'رأس المال',
        parentId: '3100',
        section: StatementSection.equity,
        normalSide: NormalSide.credit,
        sortOrder: 410,
      ),
      _posting(
        storeId: storeId,
        id: '4100',
        code: '4100',
        name: 'المبيعات',
        section: StatementSection.revenue,
        normalSide: NormalSide.credit,
        sortOrder: 500,
      ),
      _posting(
        storeId: storeId,
        id: '5100',
        code: '5100',
        name: 'تكلفة المبيعات',
        section: StatementSection.costOfSales,
        normalSide: NormalSide.debit,
        sortOrder: 600,
      ),
      _header(
        storeId: storeId,
        id: '6100',
        code: '6100',
        name: 'المصاريف التشغيلية',
        section: StatementSection.operatingExpense,
        sortOrder: 700,
      ),
      _posting(
        storeId: storeId,
        id: '6110',
        code: '6110',
        name: 'الإيجارات',
        parentId: '6100',
        section: StatementSection.operatingExpense,
        sortOrder: 710,
      ),
      _posting(
        storeId: storeId,
        id: '6120',
        code: '6120',
        name: 'الرواتب والأجور',
        parentId: '6100',
        section: StatementSection.operatingExpense,
        sortOrder: 720,
      ),
      _posting(
        storeId: storeId,
        id: '6130',
        code: '6130',
        name: 'المرافق والخدمات',
        parentId: '6100',
        section: StatementSection.operatingExpense,
        sortOrder: 730,
      ),
    ];

    _validate(accounts, storeId);
    return List.unmodifiable(accounts);
  }

  static Account _header({
    required String storeId,
    required String id,
    required String code,
    required String name,
    required StatementSection section,
    required int sortOrder,
    NormalSide normalSide = NormalSide.debit,
  }) {
    return Account(
      id: id,
      storeId: storeId,
      code: code,
      name: name,
      type: _accountTypeFor(section),
      normalSide: normalSide,
      controlType: ControlType.none,
      statementSection: section,
      isHeader: true,
      sortOrder: sortOrder,
    );
  }

  static Account _posting({
    required String storeId,
    required String id,
    required String code,
    required String name,
    required StatementSection section,
    required int sortOrder,
    String? parentId,
    ControlType controlType = ControlType.none,
    NormalSide? normalSide,
  }) {
    final resolvedSide = normalSide ?? _normalSideFor(_accountTypeFor(section));

    return Account(
      id: id,
      storeId: storeId,
      code: code,
      name: name,
      type: _accountTypeFor(section),
      normalSide: resolvedSide,
      controlType: controlType,
      statementSection: section,
      parentId: parentId,
      sortOrder: sortOrder,
    );
  }

  static AccountType _accountTypeFor(StatementSection section) {
    switch (section) {
      case StatementSection.currentAsset:
      case StatementSection.nonCurrentAsset:
        return AccountType.asset;
      case StatementSection.currentLiability:
      case StatementSection.nonCurrentLiability:
        return AccountType.liability;
      case StatementSection.equity:
        return AccountType.equity;
      case StatementSection.revenue:
      case StatementSection.otherIncome:
        return AccountType.revenue;
      case StatementSection.costOfSales:
      case StatementSection.operatingExpense:
      case StatementSection.otherExpense:
        return AccountType.expense;
    }
  }

  static NormalSide _normalSideFor(AccountType type) {
    switch (type) {
      case AccountType.asset:
      case AccountType.expense:
        return NormalSide.debit;
      case AccountType.liability:
      case AccountType.equity:
      case AccountType.revenue:
        return NormalSide.credit;
    }
  }

  static void _validate(List<Account> accounts, String storeId) {
    final ids = <String>{};
    final codes = <String>{};

    for (final account in accounts) {
      if (!ids.add(account.id)) {
        throw StateError('Duplicate account id: ${account.id}.');
      }
      if (!codes.add(account.code)) {
        throw StateError('Duplicate account code: ${account.code}.');
      }
      if (account.storeId != storeId) {
        throw StateError('Account belongs to another store: ${account.id}.');
      }
      if (account.isHeader && account.controlType != ControlType.none) {
        throw StateError('Header account cannot be a control account.');
      }
    }

    for (final account
        in accounts.where((account) => account.parentId != null)) {
      final parent = accounts
          .where((candidate) => candidate.id == account.parentId)
          .firstOrNull;
      if (parent == null || !parent.isHeader) {
        throw StateError('Invalid parent for account: ${account.id}.');
      }
    }
  }
}
