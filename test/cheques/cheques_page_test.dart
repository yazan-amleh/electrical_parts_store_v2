import 'package:electrical_parts_store_v2/core/errors/failure.dart';
import 'package:electrical_parts_store_v2/core/money/money.dart';
import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/authenticated_user.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/store_membership.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/enums/store_role.dart';
import 'package:electrical_parts_store_v2/features/cheques/domain/entities/cheque.dart';
import 'package:electrical_parts_store_v2/features/cheques/domain/entities/cheque_settlement_request.dart';
import 'package:electrical_parts_store_v2/features/cheques/domain/entities/cheque_settlement_result.dart';
import 'package:electrical_parts_store_v2/features/cheques/domain/enums/cheque_status.dart';
import 'package:electrical_parts_store_v2/features/cheques/domain/repositories/cheque_repository.dart';
import 'package:electrical_parts_store_v2/features/cheques/presentation/cheques_page.dart';
import 'package:electrical_parts_store_v2/features/parties/domain/enums/party_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Cheques implements ChequeRepository {
  _Cheques({this.queueFirst = false});

  final bool queueFirst;
  final requests = <ChequeSettlementRequest>[];
  bool settled = false;

  Cheque get pendingCheque => Cheque(
        id: 'cheque-1',
        storeId: 'store-1',
        partyType: PartyType.customer,
        partyId: 'customer-1',
        amount: const Money(minorUnits: 4200),
        chequeNumber: 'CHK-100',
        bankName: 'Test Bank',
        receivedAt: DateTime.utc(2026, 10, 20),
        status: ChequeStatus.pending,
      );

  @override
  Future<Result<List<Cheque>>> getCheques({
    required StoreContext context,
    ChequeStatus? status,
  }) async {
    final cheque = settled
        ? pendingCheque.copyWith(
            status: ChequeStatus.cleared,
            settlementJournalEntryId: 'cheque-1-cheque-clear',
          )
        : pendingCheque;
    if (status != null && cheque.status != status) {
      return const Success(<Cheque>[]);
    }
    return Success(<Cheque>[cheque]);
  }

  @override
  Future<Result<ChequeSettlementResult>> settleCheque({
    required StoreContext context,
    required ChequeSettlementRequest request,
  }) async {
    requests.add(request);
    if (requests.length == 1) {
      if (queueFirst) {
        return const FailureResult<ChequeSettlementResult>(
          QueuedFailure(commandId: 'settle-cheque-cheque-1-clear'),
        );
      }
      return const FailureResult<ChequeSettlementResult>(
        InfrastructureFailure('Unknown network outcome'),
      );
    }
    settled = true;
    return const Success(
      ChequeSettlementResult(
        chequeId: 'cheque-1',
        status: ChequeStatus.cleared,
        journalEntryId: 'cheque-1-cheque-clear',
      ),
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

Widget _page(_Cheques repository) {
  return MaterialApp(
    home: Scaffold(
      body: ChequesPage(
        repository: repository,
        user: _user,
        membership: _membership,
      ),
    ),
  );
}

Future<void> _startClear(
  WidgetTester tester,
  _Cheques repository,
) async {
  await tester.pumpWidget(_page(repository));
  await tester.pumpAndSettle();

  expect(find.text('CHK-100'), findsOneWidget);
  await tester.tap(find.text('تحصيل في البنك'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('تأكيد'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('unknown cheque outcome retries the exact settlement request',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _Cheques();

    await _startClear(tester, repository);

    expect(repository.requests, hasLength(1));
    final first = repository.requests.single;
    expect(find.text('إعادة نفس التسوية'), findsOneWidget);

    await tester.tap(find.text('إعادة نفس التسوية'));
    await tester.pumpAndSettle();

    expect(repository.requests, hasLength(2));
    final second = repository.requests.last;
    expect(identical(first, second), isTrue);
    expect(second.idempotencyKey.value, first.idempotencyKey.value);
    expect(second.postedAt, first.postedAt);
    expect(second.action, first.action);
    expect(second.bankAccountId, first.bankAccountId);
  });

  testWidgets('queued cheque settlement blocks a second settlement command',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _Cheques(queueFirst: true);

    await _startClear(tester, repository);

    expect(repository.requests, hasLength(1));
    expect(find.text('إعادة نفس التسوية'), findsNothing);
    expect(
      find.textContaining('محفوظة في طابور التنفيذ'),
      findsOneWidget,
    );
    expect(find.text('تحصيل في البنك'), findsNothing);
    expect(find.text('ارتجاع'), findsNothing);
  });
}
