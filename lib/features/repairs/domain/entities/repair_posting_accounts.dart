class RepairPostingAccounts {
  const RepairPostingAccounts({
    this.customerReceivableAccountId = '1140',
    this.repairRevenueAccountId = '4110',
    this.inventoryAccountId = '1150',
    this.costOfSalesAccountId = '5100',
    this.customerAdvancesAccountId = '2130',
    this.settlementAccountId = '1110',
    this.bankAccountId = '1121',
    this.cardReceivableAccountId = '1160',
    this.checksAccountId = '1130',
  });

  final String customerReceivableAccountId;
  final String repairRevenueAccountId;
  final String inventoryAccountId;
  final String costOfSalesAccountId;
  final String customerAdvancesAccountId;
  final String settlementAccountId;
  final String bankAccountId;
  final String cardReceivableAccountId;
  final String checksAccountId;

  Iterable<String> get allAccountIds sync* {
    yield customerReceivableAccountId;
    yield repairRevenueAccountId;
    yield inventoryAccountId;
    yield costOfSalesAccountId;
    yield customerAdvancesAccountId;
    yield settlementAccountId;
    yield bankAccountId;
    yield cardReceivableAccountId;
    yield checksAccountId;
  }

  void validate() {
    for (final accountId in allAccountIds) {
      if (accountId.trim().isEmpty || accountId.contains('/')) {
        throw ArgumentError('Repair posting account id is invalid.');
      }
    }
    final distinct = allAccountIds.toSet();
    if (distinct.length != allAccountIds.length) {
      throw ArgumentError('Repair posting accounts must be distinct.');
    }
  }
}
