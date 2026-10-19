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
  customerReceivable,
  supplierPayable,
  inventory,
  fixedAsset,
  tax,
  inputTax,
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
