import 'package:electrical_parts_store_v2/core/errors/failure.dart';
import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/authenticated_user.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/store_membership.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/enums/store_role.dart';
import 'package:electrical_parts_store_v2/features/expenses/domain/entities/expense.dart';
import 'package:electrical_parts_store_v2/features/expenses/domain/entities/expense_posting_plan.dart';
import 'package:electrical_parts_store_v2/features/expenses/domain/repositories/expense_repository.dart';
import 'package:electrical_parts_store_v2/features/expenses/presentation/expenses_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Expenses implements ExpenseRepository {
  _Expenses({this.queueFirst = false});

  final bool queueFirst;
  final posted = <Expense>[];

  @override
  Future<Result<ExpensePostingPlan>> postExpense({
    required StoreContext context,
    required Expense expense,
    required ExpensePostingAccounts accounts,
  }) async {
    posted.add(expense);
    if (posted.length == 1) {
      if (queueFirst) {
        return const FailureResult<ExpensePostingPlan>(
          QueuedFailure(commandId: 'queued-expense'),
        );
      }
      return const FailureResult<ExpensePostingPlan>(
        InfrastructureFailure('Unknown network outcome'),
      );
    }
    return const FailureResult<ExpensePostingPlan>(
      ValidationFailure('Captured retry'),
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

Widget _page(
  ExpenseRepository repository, {
  AuthenticatedUser user = _user,
  StoreMembership membership = _membership,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ExpensesPage(
        repository: repository,
        user: user,
        membership: membership,
      ),
    ),
  );
}

Future<void> _submitAmount(
  WidgetTester tester,
  String amount,
) async {
  final amountField = find.byType(TextField).first;
  await tester.enterText(amountField, amount);
  await tester.tap(find.text('ترحيل المصروف'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('unknown expense outcome retries the exact same expense object',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _Expenses();

    await tester.pumpWidget(_page(repository));
    await tester.pumpAndSettle();

    await _submitAmount(tester, '25.00');
    expect(repository.posted, hasLength(1));
    final first = repository.posted.single;

    await tester.tap(find.text('ترحيل المصروف'));
    await tester.pumpAndSettle();

    expect(repository.posted, hasLength(2));
    final second = repository.posted.last;
    expect(identical(first, second), isTrue);
    expect(second.id, first.id);
    expect(second.idempotencyKey.value, first.idempotencyKey.value);
    expect(second.postedAt, first.postedAt);
  });

  testWidgets('unknown expense outcome blocks a changed financial request',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _Expenses();

    await tester.pumpWidget(_page(repository));
    await tester.pumpAndSettle();

    await _submitAmount(tester, '25.00');
    expect(repository.posted, hasLength(1));

    final amountField = find.byType(TextField).first;
    await tester.enterText(amountField, '30.00');
    await tester.tap(find.text('ترحيل المصروف'));
    await tester.pumpAndSettle();

    expect(repository.posted, hasLength(1));
    expect(
      find.textContaining('نتيجة المصروف السابق غير محسومة'),
      findsWidgets,
    );
  });

  testWidgets('tenant change clears queued expense fence', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _Expenses(queueFirst: true);

    await tester.pumpWidget(_page(repository));
    await tester.pumpAndSettle();
    await _submitAmount(tester, '10.00');
    expect(repository.posted, hasLength(1));

    const nextMembership = StoreMembership(
      storeId: 'store-2',
      userId: 'user-1',
      role: StoreRole.owner,
    );
    await tester.pumpWidget(
      _page(repository, membership: nextMembership),
    );
    await tester.pumpAndSettle();

    await _submitAmount(tester, '11.00');
    expect(repository.posted, hasLength(2));
    expect(repository.posted.last.storeId, 'store-2');
  });

  testWidgets('non-accounting roles cannot access expense posting form',
      (tester) async {
    const viewerMembership = StoreMembership(
      storeId: 'store-1',
      userId: 'user-1',
      role: StoreRole.viewer,
    );

    await tester.pumpWidget(
      _page(_Expenses(), membership: viewerMembership),
    );
    await tester.pumpAndSettle();

    expect(find.text('ليس لديك صلاحية لترحيل المصروفات.'), findsOneWidget);
    expect(find.text('ترحيل المصروف'), findsNothing);
  });
}
