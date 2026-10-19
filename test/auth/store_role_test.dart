import 'package:flutter_test/flutter_test.dart';

import '../../lib/features/auth/domain/enums/store_role.dart';

void main() {
  test('owner and admin can manage the store', () {
    expect(StoreRole.owner.canManageStore, isTrue);
    expect(StoreRole.admin.canManageStore, isTrue);
    expect(StoreRole.accountant.canManageStore, isFalse);
  });

  test('accountant can post accounting but cannot manage inventory', () {
    expect(StoreRole.accountant.canPostAccounting, isTrue);
    expect(StoreRole.accountant.canManageInventory, isFalse);
  });

  test('sales and warehouse roles are scoped to their modules', () {
    expect(StoreRole.sales.canManageSales, isTrue);
    expect(StoreRole.sales.canManageInventory, isFalse);
    expect(StoreRole.warehouse.canManageInventory, isTrue);
    expect(StoreRole.warehouse.canManageSales, isFalse);
  });
}
