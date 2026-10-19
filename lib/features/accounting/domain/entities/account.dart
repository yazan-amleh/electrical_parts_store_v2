import '../enums/accounting_enums.dart';

class Account {
  const Account({
    required this.id,
    required this.storeId,
    required this.code,
    required this.name,
    required this.type,
    required this.normalSide,
    required this.controlType,
    required this.statementSection,
    this.currency = 'ILS',
    this.isActive = true,
  });

  final String id;
  final String storeId;
  final String code;
  final String name;
  final AccountType type;
  final NormalSide normalSide;
  final ControlType controlType;
  final StatementSection statementSection;
  final String currency;
  final bool isActive;
}
