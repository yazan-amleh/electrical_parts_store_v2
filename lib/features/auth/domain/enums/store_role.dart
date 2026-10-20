enum StoreRole { owner, admin, accountant, sales, warehouse, viewer }

extension StoreRoleCapabilities on StoreRole {
  bool get canManageStore {
    return this == StoreRole.owner || this == StoreRole.admin;
  }

  bool get canPostAccounting {
    return canManageStore || this == StoreRole.accountant;
  }

  bool get canManageSales {
    return canManageStore || this == StoreRole.sales;
  }

  bool get canManageInventory {
    return canManageStore || this == StoreRole.warehouse;
  }
}
