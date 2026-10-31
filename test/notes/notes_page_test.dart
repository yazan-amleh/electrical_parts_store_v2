import 'dart:async';

import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/authenticated_user.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/store_membership.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/enums/store_role.dart';
import 'package:electrical_parts_store_v2/features/notes/domain/entities/note.dart';
import 'package:electrical_parts_store_v2/features/notes/domain/enums/note_enums.dart';
import 'package:electrical_parts_store_v2/features/notes/domain/repositories/note_repository.dart';
import 'package:electrical_parts_store_v2/features/notes/presentation/notes_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _NotesRepository implements NoteRepository {
  _NotesRepository(this.notesByStore, {this.pendingStoreB});

  final Map<String, List<Note>> notesByStore;
  final Completer<Result<List<Note>>>? pendingStoreB;
  final List<StoreContext> reads = <StoreContext>[];
  final List<StoreContext> deletes = <StoreContext>[];

  @override
  Future<Result<List<Note>>> getNotes({
    required StoreContext context,
    bool includeArchived = false,
    bool starredOnly = false,
  }) {
    reads.add(context);
    if (context.storeId == 'store-b' && pendingStoreB != null) {
      return pendingStoreB!.future;
    }
    return Future<Result<List<Note>>>.value(
      Success<List<Note>>(notesByStore[context.storeId] ?? <Note>[]),
    );
  }

  @override
  Future<Result<void>> saveNote({
    required StoreContext context,
    required Note note,
  }) async {
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> deleteNote({
    required StoreContext context,
    required Note note,
  }) async {
    deletes.add(context);
    notesByStore[context.storeId]?.removeWhere((item) => item.id == note.id);
    return const Success<void>(null);
  }
}

const _user = AuthenticatedUser(id: 'user-1', email: 'owner@example.com');

Note _note(
  String storeId,
  String name, {
  bool starred = false,
  bool archived = false,
}) {
  return Note(
    id: name,
    storeId: storeId,
    userId: _user.id,
    title: name,
    content: 'نص الملاحظة',
    type: NoteType.general,
    priority: NotePriority.medium,
    createdAt: DateTime.utc(2026, 10, 30),
    isStarred: starred,
    isArchived: archived,
  );
}

Widget _page(_NotesRepository repository, String storeId) {
  return MaterialApp(
    home: NotesPage(
      repository: repository,
      user: _user,
      membership: StoreMembership(
        storeId: storeId,
        userId: _user.id,
        role: StoreRole.owner,
      ),
    ),
  );
}

void main() {
  testWidgets('notes rebind to the active store without stale content', (
    tester,
  ) async {
    final repository = _NotesRepository({
      'store-a': [_note('store-a', 'ملاحظة المتجر أ')],
      'store-b': [_note('store-b', 'ملاحظة المتجر ب')],
    });
    await tester.pumpWidget(_page(repository, 'store-a'));
    await tester.pumpAndSettle();
    expect(find.text('ملاحظة المتجر أ'), findsOneWidget);

    await tester.pumpWidget(_page(repository, 'store-b'));
    await tester.pumpAndSettle();
    expect(find.text('ملاحظة المتجر أ'), findsNothing);
    expect(find.text('ملاحظة المتجر ب'), findsOneWidget);
    expect(repository.reads.last.storeId, 'store-b');
  });

  testWidgets('a pending next-store load never displays prior store notes', (
    tester,
  ) async {
    final pending = Completer<Result<List<Note>>>();
    final repository = _NotesRepository({
      'store-a': [_note('store-a', 'بيانات خاصة بالمتجر أ')],
    }, pendingStoreB: pending);

    await tester.pumpWidget(_page(repository, 'store-a'));
    await tester.pumpAndSettle();
    expect(find.text('بيانات خاصة بالمتجر أ'), findsOneWidget);

    await tester.pumpWidget(_page(repository, 'store-b'));
    await tester.pump();
    expect(find.text('بيانات خاصة بالمتجر أ'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pending.complete(Success<List<Note>>([
      _note('store-b', 'بيانات المتجر ب'),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('بيانات المتجر ب'), findsOneWidget);
    expect(find.text('بيانات خاصة بالمتجر أ'), findsNothing);
  });

  testWidgets('restores V1 active, starred and archived note views', (
    tester,
  ) async {
    final repository = _NotesRepository({
      'store-a': [
        _note('store-a', 'ملاحظة نشطة', starred: true),
        _note('store-a', 'ملاحظة مؤرشفة', archived: true),
      ],
    });

    await tester.pumpWidget(_page(repository, 'store-a'));
    await tester.pumpAndSettle();
    expect(find.text('ملاحظة نشطة'), findsOneWidget);
    expect(find.text('ملاحظة مؤرشفة'), findsNothing);

    await tester.tap(find.text('المميزة بنجمة'));
    await tester.pumpAndSettle();
    expect(find.text('ملاحظة نشطة'), findsOneWidget);
    expect(find.text('ملاحظة مؤرشفة'), findsNothing);

    await tester.tap(find.text('المؤرشفة'));
    await tester.pumpAndSettle();
    expect(find.text('ملاحظة مؤرشفة'), findsOneWidget);
    expect(find.text('ملاحظة نشطة'), findsNothing);
  });

  testWidgets('V1 delete note requires confirmation and stays in the store', (
    tester,
  ) async {
    final repository = _NotesRepository({
      'store-a': [_note('store-a', 'ملاحظة قابلة للحذف')],
    });
    await tester.pumpWidget(_page(repository, 'store-a'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف الملاحظة'));
    await tester.pumpAndSettle();
    expect(find.text('تأكيد الحذف'), findsOneWidget);

    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(repository.deletes, isEmpty);
    expect(find.text('ملاحظة قابلة للحذف'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف الملاحظة'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'حذف'));
    await tester.pumpAndSettle();

    expect(repository.deletes, hasLength(1));
    expect(repository.deletes.single.storeId, 'store-a');
    expect(find.text('ملاحظة قابلة للحذف'), findsNothing);
  });
}
