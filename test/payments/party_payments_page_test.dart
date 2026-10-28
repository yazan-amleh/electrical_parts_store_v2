import 'package:electrical_parts_store_v2/core/errors/failure.dart';
import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/authenticated_user.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/store_membership.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/enums/store_role.dart';
import 'package:electrical_parts_store_v2/features/parties/domain/entities/party.dart';
import 'package:electrical_parts_store_v2/features/parties/domain/entities/party_balance.dart';
import 'package:electrical_parts_store_v2/features/parties/domain/enums/party_type.dart';
import 'package:electrical_parts_store_v2/features/parties/domain/repositories/party_repository.dart';
import 'package:electrical_parts_store_v2/features/payments/domain/entities/party_payment.dart';
import 'package:electrical_parts_store_v2/features/payments/domain/entities/party_payment_posting_plan.dart';
import 'package:electrical_parts_store_v2/features/payments/domain/repositories/party_payment_repository.dart';
import 'package:electrical_parts_store_v2/features/payments/presentation/party_payments_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Parties implements PartyRepository {
  final calls = <PartyType>[];

  @override
  Future<Result<List<Party>>> getParties({
    required StoreContext context,
    required PartyType type,
    bool includeInactive = false,
  }) async {
    calls.add(type);
    if (type == PartyType.customer) {
      return Success(<Party>[
        Party(
          id: 'customer-1',
          storeId: context.storeId,
          type: PartyType.customer,
          name: 'Alice Customer',
          phone: '0599000001',
        ),
      ]);
    }
    return Success(<Party>[
      Party(
        id: 'supplier-1',
        storeId: context.storeId,
        type: PartyType.supplier,
        name: 'Best Supplier',
        phone: '0599000002',
      ),
    ]);
  }

  @override
  Future<Result<Map<String, PartyBalance>>> getBalances({
    required StoreContext context,
    required PartyType type,
  }) async {
    return const Success(<String, PartyBalance>{});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Payments implements PartyPaymentRepository {
  final posted = <PartyPayment>[];

  @override
  Future<Result<PartyPaymentPostingPlan>> postPartyPayment({
    required StoreContext context,
    required PartyPayment payment,
    required PartyPaymentPostingAccounts accounts,
  }) async {
    posted.add(payment);
    return const FailureResult<PartyPaymentPostingPlan>(
      ValidationFailure('Captured for widget test'),
    );
  }
}

const _user = AuthenticatedUser(
  id: 'user-1',
  email: 'test@example.com',
);

const _membership = StoreMembership(
  storeId: 'store-1',
  userId: 'user-1',
  role: StoreRole.owner,
);

Widget _page(_Payments payments, _Parties parties, {String? initialPartyId}) {
  return MaterialApp(
    home: Scaffold(
      body: PartyPaymentsPage(
        repository: payments,
        partyRepository: parties,
        user: _user,
        membership: _membership,
        initialPartyId: initialPartyId,
      ),
    ),
  );
}

void main() {
  testWidgets('searchable customer selection posts the party id, not its name',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final payments = _Payments();
    final parties = _Parties();

    await tester.pumpWidget(_page(payments, parties));
    await tester.pumpAndSettle();

    final search = find.byKey(
      const ValueKey('party-payment-party-search'),
    );
    expect(search, findsOneWidget);
    await tester.enterText(search, 'Alice');
    await tester.pumpAndSettle();

    final option = find.text('Alice Customer');
    expect(option, findsOneWidget);
    await tester.tap(option);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('party-payment-amount')),
      '12.50',
    );
    await tester.tap(
      find.byKey(const ValueKey('party-payment-submit')),
    );
    await tester.pumpAndSettle();

    expect(payments.posted, hasLength(1));
    expect(payments.posted.single.partyId, 'customer-1');
    expect(payments.posted.single.partyType, PartyType.customer);
    expect(payments.posted.single.amount, const Money(minorUnits: 1250));
  });

  testWidgets('switching to supplier reloads and isolates the party list',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final payments = _Payments();
    final parties = _Parties();

    await tester.pumpWidget(_page(payments, parties));
    await tester.pumpAndSettle();
    expect(parties.calls, contains(PartyType.customer));

    await tester.tap(find.text('مورد'));
    await tester.pumpAndSettle();

    expect(parties.calls.last, PartyType.supplier);
    final search = find.byKey(
      const ValueKey('party-payment-party-search'),
    );
    await tester.enterText(search, 'Best');
    await tester.pumpAndSettle();

    expect(find.text('Best Supplier'), findsOneWidget);
    expect(find.text('Alice Customer'), findsNothing);
  });

  testWidgets('initial party id resolves to its display name', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final payments = _Payments();
    final parties = _Parties();

    await tester.pumpWidget(
      _page(payments, parties, initialPartyId: 'customer-1'),
    );
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('party-payment-party-search')),
    );
    expect(field.controller!.text, 'Alice Customer');
  });
}
