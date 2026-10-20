enum AccountType {
  asset,
  liability,
  equity,
  revenue,
  expense,
}

enum NormalSide {
  debit,
  credit,
}

enum ControlType {
  none,
  cashBox,
  bank,
  checks,
  customerReceivable,
  supplierPayable,
  inventory,
  fixedAsset,
  tax,
  inputTax,
  cardReceivable,
}

enum StatementSection {
  currentAsset,
  nonCurrentAsset,
  currentLiability,
  nonCurrentLiability,
  equity,
  revenue,
  costOfSales,
  operatingExpense,
  otherIncome,
  otherExpense,
}
