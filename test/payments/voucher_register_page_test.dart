import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/authenticated_user.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/store_membership.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/enums/store_role.dart';
import 'package:electrical_parts_store_v2/features/parties/domain/enums/party_type.dart';
import 'package:electrical_parts_store_v2/features/payments/domain/entities/voucher_record.dart';
import 'package:electrical_parts_store_v2/features/payments/domain/enums/party_payment_method.dart';
import 'package:electrical_parts_store_v2/features/payments/domain/repositories/voucher_query_repository.dart';
import 'package:electrical_parts_store_v2/features/payments/presentation/voucher_register_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _PageRepository implements VoucherQueryRepository {
  int calls = 0;

  @override
  Future<Result<VoucherPage>> getVoucherPage({
    required StoreContext context,
    VoucherCursor? after,
    int pageSize = 50,
  }) async {
    calls++;
    final id = after == null ? 'voucher-1' : 'voucher-2';
    return Success<VoucherPage>(
      VoucherPage(
        records: [
          VoucherRecord(
            id: id,
            storeId: context.storeId,
            partyType: PartyType.customer,
            partyId: 'customer-a',
            paymentMethod: PartyPaymentMethod.cash,
            amount: Money(minorUnits: 12500, currency: 'ILS'),
            postedAt: DateTime.utc(2026, 10, 26, 10),
            journalEntryId: '$id-journal',
            status: 'posted',
          ),
        ],
        hasMore: after == null,
        nextCursor: after == null
            ? VoucherCursor(
                id: id,
                postedAt: DateTime.utc(2026, 10, 26, 10),
              )
            : null,
      ),
    );
  }
}

void main() {
  testWidgets('voucher register loads more financial documents on demand',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1040, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _PageRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoucherRegisterPage(
            repository: repository,
            user: const AuthenticatedUser(
              id: 'user-a',
              email: 'user@example.com',
            ),
            membership: StoreMembership(
              storeId: 'store-a',
              userId: 'user-a',
              role: StoreRole.accountant,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.calls, 1);
    expect(find.textContaining('voucher-1'), findsWidgets);
    await tester.tap(find.text('تحميل 50 سندًا إضافيًا'));
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
    expect(find.textContaining('voucher-2'), findsWidgets);
    expect(find.text('تحميل 50 سندًا إضافيًا'), findsNothing);
  });
}
