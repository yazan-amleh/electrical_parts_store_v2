import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/chat/domain/entities/chat_message.dart';
import 'package:electrical_parts_store_v2/features/chat/domain/repositories/chat_repository.dart';
import 'package:electrical_parts_store_v2/features/chat/presentation/chat_message_search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _SearchRepository implements ChatRepository {
  final List<StoreContext> calls = <StoreContext>[];

  @override
  Stream<Result<List<ChatMessage>>> watchMessages({
    required StoreContext context,
    required String roomId,
  }) {
    calls.add(context);
    final now = DateTime.utc(2026, 10, 31);
    ChatMessage message(String id, String text, String room) => ChatMessage(
          id: id,
          roomId: room,
          storeId: context.storeId,
          senderId: 'user-2',
          senderName: 'موظف المبيعات',
          content: text,
          sentAt: now,
        );
    return Stream<Result<List<ChatMessage>>>.value(
      Success<List<ChatMessage>>([
        message('a', 'طلب صيانة الكهرباء', roomId),
        message('b', 'فاتورة العميل', roomId),
        message('other', 'طلب صيانة من غرفة أخرى', 'other-room'),
      ]),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('search only returns messages from the requested chat room', (
    tester,
  ) async {
    final repository = _SearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ChatMessageSearchPage(
          repository: repository,
          storeContext: const StoreContext(
            storeId: 'store-a',
            userId: 'user-1',
          ),
          roomId: 'room-1',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('اكتب كلمة للبحث داخل هذه المحادثة.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'صيانة');
    await tester.pumpAndSettle();
    expect(find.text('النتائج: 1'), findsOneWidget);
    expect(find.text('طلب صيانة الكهرباء'), findsOneWidget);
    expect(find.text('فاتورة العميل'), findsNothing);
    expect(repository.calls.single.storeId, 'store-a');

    await tester.tap(find.text('طلب صيانة الكهرباء'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
  });
}
