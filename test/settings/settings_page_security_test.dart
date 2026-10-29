import 'dart:async';

import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/authenticated_user.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/store_membership.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/enums/store_role.dart';
import 'package:electrical_parts_store_v2/features/settings/domain/entities/store_member.dart';
import 'package:electrical_parts_store_v2/features/settings/domain/entities/store_profile.dart';
import 'package:electrical_parts_store_v2/features/settings/domain/repositories/settings_repository.dart';
import 'package:electrical_parts_store_v2/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Settings implements SettingsRepository {
  _Settings({this.delayedProfiles = false});

  final bool delayedProfiles;
  int memberReads = 0;
  final Map<String, Completer<Result<StoreProfile>>> profileCompleters = {};

  @override
  Future<Result<StoreProfile>> getStoreProfile({
    required StoreContext context,
  }) async {
    if (delayedProfiles) {
      return profileCompleters
          .putIfAbsent(
            context.storeId,
            () => Completer<Result<StoreProfile>>(),
          )
          .future;
    }
    return Success(
      StoreProfile(
        id: context.storeId,
        name: 'Store ${context.storeId}',
        currency: 'ILS',
        phone: '',
        address: '',
      ),
    );
  }

  @override
  Future<Result<List<StoreMember>>> getMembers({
    required StoreContext context,
  }) async {
    memberReads++;
    return Success(<StoreMember>[
      const StoreMember(
        userId: 'owner-1',
        role: StoreRole.owner,
        isActive: true,
      ),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _user = AuthenticatedUser(
  id: 'user-1',
  email: 'user@example.com',
);

StoreMembership _membership(String storeId, StoreRole role) {
  return StoreMembership(
    storeId: storeId,
    userId: _user.id,
    role: role,
  );
}

Widget _page(
  SettingsRepository repository,
  StoreMembership membership,
) {
  return MaterialApp(
    home: Scaffold(
      body: SettingsPage(
        repository: repository,
        user: _user,
        membership: membership,
      ),
    ),
  );
}

void main() {
  testWidgets('viewer loads store profile without enumerating members',
      (tester) async {
    final repository = _Settings();

    await tester.pumpWidget(
      _page(repository, _membership('store-view', StoreRole.viewer)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Store store-view'), findsOneWidget);
    expect(
      find.text('قائمة الأعضاء والصلاحيات متاحة للمالك والمدير فقط.'),
      findsOneWidget,
    );
    expect(repository.memberReads, 0);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('stale profile result cannot overwrite a new tenant',
      (tester) async {
    final repository = _Settings(delayedProfiles: true);

    await tester.pumpWidget(
      _page(repository, _membership('store-a', StoreRole.viewer)),
    );
    await tester.pump();

    await tester.pumpWidget(
      _page(repository, _membership('store-b', StoreRole.viewer)),
    );
    await tester.pump();

    repository.profileCompleters['store-b']!.complete(
      Success(
        StoreProfile(
          id: 'store-b',
          name: 'Store B',
          currency: 'ILS',
          phone: '',
          address: '',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Store B'), findsOneWidget);

    repository.profileCompleters['store-a']!.complete(
      const Success(
        StoreProfile(
          id: 'store-a',
          name: 'STALE STORE A',
          currency: 'ILS',
          phone: '',
          address: '',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Store B'), findsOneWidget);
    expect(find.text('STALE STORE A'), findsNothing);
  });
}
