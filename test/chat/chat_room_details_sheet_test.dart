import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/enums/store_role.dart';
import 'package:electrical_parts_store_v2/features/chat/domain/entities/chat_participant.dart';
import 'package:electrical_parts_store_v2/features/chat/domain/entities/chat_room.dart';
import 'package:electrical_parts_store_v2/features/chat/domain/repositories/chat_repository.dart';
import 'package:electrical_parts_store_v2/features/chat/presentation/chat_room_details_sheet.dart';
import 'package:electrical_parts_store_v2/features/settings/domain/entities/store_member.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _GroupRepository implements ChatRepository {
  int edits = 0;
  int invites = 0;
  String? lastName;
  String? invitedId;

  @override
  Future<Result<void>> updateRoom({
    required StoreContext context,
    required String roomId,
    String? name,
    String? groupDescription,
  }) async {
    edits++;
    lastName = name;
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> addParticipant({
    required StoreContext context,
    required String roomId,
    required ChatParticipant participant,
  }) async {
    invites++;
    invitedId = participant.userId;
    return const Success<void>(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _joined = DateTime.utc(2026, 10, 31);

ChatRoom _room() => ChatRoom(
      id: 'room-1',
      storeId: 'store-a',
      name: 'الفريق',
      participantIds: const ['owner-1', 'user-2'],
      participants: [
        ChatParticipant(
          userId: 'owner-1',
          displayName: 'المالك',
          joinedAt: _joined,
          isAdmin: true,
        ),
        ChatParticipant(
          userId: 'user-2',
          displayName: 'المحاسب',
          joinedAt: _joined,
        ),
      ],
      createdAt: _joined,
      createdBy: 'owner-1',
      isGroup: true,
    );

const _members = <StoreMember>[
  StoreMember(
    userId: 'user-3',
    role: StoreRole.sales,
    isActive: true,
    displayName: 'موظف الصيانة',
  ),
];

Widget _page(_GroupRepository repository, StoreRole role, String userId) {
  return MaterialApp(
    home: Scaffold(
      body: ChatRoomDetailsSheet(
        room: _room(),
        contextForStore: StoreContext(storeId: 'store-a', userId: userId),
        currentRole: role,
        repository: repository,
        availableMembers: _members,
      ),
    ),
  );
}

void main() {
  testWidgets('group owner can edit group name and invite an active member', (
    tester,
  ) async {
    final repository = _GroupRepository();
    await tester.pumpWidget(_page(repository, StoreRole.owner, 'owner-1'));

    await tester.tap(find.byTooltip('تعديل معلومات المجموعة'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'مجموعة الحسابات');
    await tester.tap(find.widgetWithText(FilledButton, 'حفظ'));
    await tester.pumpAndSettle();
    expect(repository.edits, 1);
    expect(repository.lastName, 'مجموعة الحسابات');

    await tester.tap(find.text('إضافة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('موظف الصيانة'));
    await tester.pumpAndSettle();
    expect(repository.invites, 1);
    expect(repository.invitedId, 'user-3');
  });

  testWidgets('regular participant sees info without mutation actions', (
    tester,
  ) async {
    final repository = _GroupRepository();
    await tester.pumpWidget(_page(repository, StoreRole.sales, 'user-2'));
    await tester.pumpAndSettle();
    expect(find.text('المحاسب'), findsOneWidget);
    expect(find.byTooltip('تعديل معلومات المجموعة'), findsNothing);
    expect(find.text('إضافة'), findsNothing);
  });
}
