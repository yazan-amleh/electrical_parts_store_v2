import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/authenticated_user.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/store_membership.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/enums/store_role.dart';
import 'package:electrical_parts_store_v2/features/chat/domain/entities/chat_participant.dart';
import 'package:electrical_parts_store_v2/features/chat/domain/entities/chat_room.dart';
import 'package:electrical_parts_store_v2/features/chat/domain/repositories/chat_repository.dart';
import 'package:electrical_parts_store_v2/features/chat/presentation/chat_page.dart';
import 'package:electrical_parts_store_v2/features/settings/domain/entities/store_member.dart';
import 'package:electrical_parts_store_v2/features/settings/domain/repositories/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ChatRooms implements ChatRepository {
  _ChatRooms(this.byStore);

  final Map<String, List<ChatRoom>> byStore;
  final List<StoreContext> reads = [];

  @override
  Stream<Result<List<ChatRoom>>> watchRooms({
    required StoreContext context,
  }) {
    reads.add(context);
    return Stream<Result<List<ChatRoom>>>.value(
      Success<List<ChatRoom>>(byStore[context.storeId] ?? const <ChatRoom>[]),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Members implements SettingsRepository {
  @override
  Future<Result<List<StoreMember>>> getMembers({
    required StoreContext context,
  }) async {
    return const Success<List<StoreMember>>(<StoreMember>[]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _user = AuthenticatedUser(id: 'user-1', email: 'staff@example.com');

ChatRoom _room(
  String storeId,
  String id,
  String name, {
  bool group = false,
}) {
  final joinedAt = DateTime.utc(2026, 10, 30);
  return ChatRoom(
    id: id,
    storeId: storeId,
    name: name,
    participantIds: const ['user-1', 'user-2'],
    participants: [
      ChatParticipant(
        userId: 'user-1',
        displayName: 'عضو أول',
        joinedAt: joinedAt,
      ),
      ChatParticipant(
        userId: 'user-2',
        displayName: 'فريق الصيانة',
        joinedAt: joinedAt,
      ),
    ],
    createdAt: joinedAt,
    createdBy: 'user-1',
    isGroup: group,
  );
}

Widget _page(_ChatRooms repository, String storeId) {
  return MaterialApp(
    home: ChatPage(
      repository: repository,
      settingsRepository: _Members(),
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
  testWidgets('V1-style chat list filters direct and group rooms', (
    tester,
  ) async {
    final repository = _ChatRooms({
      'store-a': [
        _room('store-a', 'direct-1', 'محاسبة الموردين'),
        _room('store-a', 'group-1', 'مجموعة المستودع', group: true),
      ],
    });
    await tester.pumpWidget(_page(repository, 'store-a'));
    await tester.pumpAndSettle();
    expect(find.text('محاسبة الموردين'), findsOneWidget);
    expect(find.text('مجموعة المستودع'), findsOneWidget);

    await tester.tap(find.text('مجموعات'));
    await tester.pumpAndSettle();
    expect(find.text('محاسبة الموردين'), findsNothing);
    expect(find.text('مجموعة المستودع'), findsOneWidget);

    await tester.tap(find.text('فردية'));
    await tester.pumpAndSettle();
    expect(find.text('محاسبة الموردين'), findsOneWidget);
    expect(find.text('مجموعة المستودع'), findsNothing);
  });

  testWidgets('search matches participants and resets when store changes', (
    tester,
  ) async {
    final repository = _ChatRooms({
      'store-a': [_room('store-a', 'a1', 'مبيعات')],
      'store-b': [_room('store-b', 'b1', 'مشتريات')],
    });
    await tester.pumpWidget(_page(repository, 'store-a'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'الصيانة');
    await tester.pump();
    expect(find.text('مبيعات'), findsOneWidget);

    await tester.pumpWidget(_page(repository, 'store-b'));
    await tester.pumpAndSettle();
    expect(find.text('مبيعات'), findsNothing);
    expect(find.text('مشتريات'), findsOneWidget);
    expect(repository.reads.last.storeId, 'store-b');
  });
}
