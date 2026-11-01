import 'dart:async';

import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/authenticated_user.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/store_membership.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/enums/store_role.dart';
import 'package:electrical_parts_store_v2/features/parties/domain/entities/party.dart';
import 'package:electrical_parts_store_v2/features/parties/domain/entities/party_ledger_entry.dart';
import 'package:electrical_parts_store_v2/features/parties/domain/enums/party_type.dart';
import 'package:electrical_parts_store_v2/features/parties/domain/repositories/party_ledger_repository.dart';
import 'package:electrical_parts_store_v2/features/parties/presentation/party_ledger_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _user = AuthenticatedUser(
  id: 'user-1',
  email: 'test@example.com',
);

const _membership = StoreMembership(
  storeId: 'store-1',
  userId: 'user-1',
  role: StoreRole.owner,
);

Party _party(String id, String name) {
  return Party(
    id: id,
    storeId: 'store-1',
    type: PartyType.customer,
    name: name,
  );
}

PartyLedgerEntry _entry(
  String id,
  String partyId, {
  required int debit,
  required int credit,
  required DateTime postedAt,
}) {
  return PartyLedgerEntry(
    id: id,
    storeId: 'store-1',
    partyType: PartyType.customer,
    partyId: partyId,
    sourceType: 'sale',
    sourceId: 'source-$id',
    postedAt: postedAt,
    debit: Money(minorUnits: debit),
    credit: Money(minorUnits: credit),
  );
}

class _LedgerRepository implements PartyLedgerRepository {
  _LedgerRepository({
    required this.entries,
    required this.balance,
  });

  final List<PartyLedgerEntry> entries;
  final Money balance;

  @override
  Future<Result<List<PartyLedgerEntry>>> getEntries({
    required StoreContext context,
    required PartyType partyType,
    required String partyId,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async {
    return Success(
      entries.where((entry) => entry.partyId == partyId).toList(),
    );
  }

  @override
  Future<Result<Money>> getBalance({
    required StoreContext context,
    required PartyType partyType,
    required String partyId,
    String currency = 'ILS',
  }) async {
    return Success(balance);
  }
}

class _SwitchingLedgerRepository implements PartyLedgerRepository {
  final firstEntries = Completer<Result<List<PartyLedgerEntry>>>();

  @override
  Future<Result<List<PartyLedgerEntry>>> getEntries({
    required StoreContext context,
    required PartyType partyType,
    required String partyId,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) {
    if (partyId == 'customer-old') {
      return firstEntries.future;
    }
    return Future.value(
      Success(<PartyLedgerEntry>[
        _entry(
          'new-entry',
          partyId,
          debit: 2500,
          credit: 0,
          postedAt: DateTime.utc(2026, 10, 29, 10),
        ),
      ]),
    );
  }

  @override
  Future<Result<Money>> getBalance({
    required StoreContext context,
    required PartyType partyType,
    required String partyId,
    String currency = 'ILS',
  }) async {
    return Success(
      Money(minorUnits: partyId == 'customer-new' ? 2500 : 9900),
    );
  }
}

Widget _page(PartyLedgerRepository repository, Party party) {
  return MaterialApp(
    home: Scaffold(
      body: PartyLedgerPage(
        repository: repository,
        user: _user,
        membership: _membership,
        party: party,
      ),
    ),
  );
}

void main() {
  testWidgets(
      'running balance uses calculated opening balance and ends at projection',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final party = _party('customer-1', 'Alice');
    final repository = _LedgerRepository(
      entries: <PartyLedgerEntry>[
        _entry(
          'entry-1',
          party.id,
          debit: 3000,
          credit: 0,
          postedAt: DateTime.utc(2026, 10, 28, 10),
        ),
        _entry(
          'entry-2',
          party.id,
          debit: 0,
          credit: 1000,
          postedAt: DateTime.utc(2026, 10, 29, 10),
        ),
      ],
      balance: const Money(minorUnits: 10000),
    );

    await tester.pumpWidget(_page(repository, party));
    await tester.pumpAndSettle();

    // Loaded delta is +20.00, so the calculated opening balance is 80.00.
    // Running balances must therefore be 110.00 then 100.00.
    expect(find.text('الرصيد الجاري: 110.00 ILS'), findsOneWidget);
    expect(find.text('الرصيد الجاري: 100.00 ILS'), findsOneWidget);
    expect(find.text('100.00 ILS'), findsWidgets);
  });

  testWidgets('late result from previous party cannot overwrite new statement',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = _SwitchingLedgerRepository();
    final oldParty = _party('customer-old', 'Old Customer');
    final newParty = _party('customer-new', 'New Customer');

    await tester.pumpWidget(_page(repository, oldParty));
    await tester.pump();

    await tester.pumpWidget(_page(repository, newParty));
    await tester.pumpAndSettle();

    expect(find.text('New Customer'), findsOneWidget);
    expect(find.text('الرصيد الجاري: 25.00 ILS'), findsOneWidget);

    repository.firstEntries.complete(
      Success(<PartyLedgerEntry>[
        _entry(
          'old-entry',
          oldParty.id,
          debit: 9900,
          credit: 0,
          postedAt: DateTime.utc(2026, 10, 27, 10),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('New Customer'), findsOneWidget);
    expect(find.text('Old Customer'), findsNothing);
    expect(find.text('الرصيد الجاري: 25.00 ILS'), findsOneWidget);
    expect(find.text('الرصيد الجاري: 99.00 ILS'), findsNothing);
  });
}
