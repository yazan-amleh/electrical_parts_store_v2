import 'dart:async';

import 'package:electrical_parts_store_v2/core/errors/failure.dart';
import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/auth/application/auth_session_controller.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/authenticated_user.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/store_membership.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/enums/store_role.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/repositories/auth_repository.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/repositories/store_membership_repository.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/repositories/store_onboarding_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('revoked membership immediately removes access to the open store',
      () async {
    final auth = _FakeAuth();
    final repo = _FakeMembership();
    final onboarding = _FakeOnboarding();
    final session = AuthSessionController(
      authRepository: auth,
      membershipRepository: repo,
      onboardingRepository: onboarding,
      storeId: 'store-1',
    )..start();

    await session.signIn(email: 'owner@test.com', password: 'secret');
    expect(session.status, AuthSessionStatus.ready);
    expect(session.membership?.role, StoreRole.owner);

    repo.emit('store-1', const FailureResult<StoreMembership>(
      AuthorizationFailure('Membership was revoked.'),
    ));
    expect(session.membership, isNull);
    expect(session.status, AuthSessionStatus.storeSetupRequired);
    expect(session.errorMessage, contains('revoked'));

    session.dispose();
    await repo.dispose();
    await auth.dispose();
  });

  test('role downgrade replaces current role without signing out', () async {
    final auth = _FakeAuth();
    final repo = _FakeMembership();
    final session = AuthSessionController(
      authRepository: auth,
      membershipRepository: repo,
      storeId: 'store-1',
    )..start();

    await session.signIn(email: 'owner@test.com', password: 'secret');
    var notifications = 0;
    session.addListener(() => notifications++);
    repo.emit('store-1', const Success<StoreMembership>(
      StoreMembership(storeId: 'store-1', userId: 'user-1', role: StoreRole.viewer),
    ));
    expect(session.status, AuthSessionStatus.ready);
    expect(session.membership?.role, StoreRole.viewer);
    expect(notifications, greaterThan(0));

    session.dispose();
    await repo.dispose();
    await auth.dispose();
  });

  test('old store updates cannot affect new selected store', () async {
    final auth = _FakeAuth();
    final repo = _FakeMembership();
    final onboarding = _FakeOnboarding();
    final session = AuthSessionController(
      authRepository: auth,
      membershipRepository: repo,
      onboardingRepository: onboarding,
      storeId: 'store-1',
    )..start();

    await session.signIn(email: 'owner@test.com', password: 'secret');
    session.openStoreSetup();
    expect(session.membership, isNull);
    await session.selectStore(storeId: 'store-2');
    expect(session.status, AuthSessionStatus.ready);
    expect(session.storeId, 'store-2');

    repo.emit('store-1', const FailureResult<StoreMembership>(
      AuthorizationFailure('Previous store revoked.'),
    ));
    expect(session.status, AuthSessionStatus.ready);
    expect(session.membership?.storeId, 'store-2');

    repo.emit('store-2', const Success<StoreMembership>(
      StoreMembership(
        storeId: 'store-2', userId: 'user-1', role: StoreRole.accountant,
      ),
    ));
    expect(session.membership?.role, StoreRole.accountant);

    session.dispose();
    await repo.dispose();
    await auth.dispose();
  });

  test('sign out removes previous watcher and refuses late re-entry', () async {
    final auth = _FakeAuth();
    final repo = _FakeMembership();
    final session = AuthSessionController(
      authRepository: auth,
      membershipRepository: repo,
      storeId: 'store-1',
    )..start();

    await session.signIn(email: 'owner@test.com', password: 'secret');
    await session.signOut();
    repo.emit('store-1', const Success<StoreMembership>(
      StoreMembership(storeId: 'store-1', userId: 'user-1', role: StoreRole.owner),
    ));
    expect(session.status, AuthSessionStatus.signedOut);
    expect(session.user, isNull);
    expect(session.membership, isNull);

    session.dispose();
    await repo.dispose();
    await auth.dispose();
  });

  test('offline membership verification removes ready state and recovers',
      () async {
    final auth = _FakeAuth();
    final repo = _FakeMembership();
    final session = AuthSessionController(
      authRepository: auth,
      membershipRepository: repo,
      storeId: 'store-1',
    )..start();

    await session.signIn(email: 'owner@test.com', password: 'secret');
    repo.emit('store-1', const FailureResult<StoreMembership>(
      InfrastructureFailure('Server not reachable.'),
    ));
    expect(session.status, AuthSessionStatus.failure);
    expect(session.membership, isNull);

    repo.emit('store-1', const Success<StoreMembership>(
      StoreMembership(storeId: 'store-1', userId: 'user-1', role: StoreRole.owner),
    ));
    expect(session.status, AuthSessionStatus.ready);

    session.dispose();
    await repo.dispose();
    await auth.dispose();
  });

  test('late sign-in completion never resurrects a logged-out session',
      () async {
    final auth = _DelayedAuth();
    final repo = _FakeMembership();
    final session = AuthSessionController(
      authRepository: auth,
      membershipRepository: repo,
      storeId: 'store-1',
    )..start();

    final pending = session.signIn(email: 'owner@test.com', password: 'secret');
    expect(session.status, AuthSessionStatus.signingIn);
    await session.signOut();
    auth.completeSignIn();
    await pending;

    expect(session.status, AuthSessionStatus.signedOut);
    expect(session.user, isNull);
    expect(session.membership, isNull);
    session.dispose();
    await repo.dispose();
    await auth.dispose();
  });

  test('rejects a repository membership belonging to a different tenant',
      () async {
    final auth = _FakeAuth();
    final repo = _WrongMembership();
    final session = AuthSessionController(
      authRepository: auth,
      membershipRepository: repo,
      storeId: 'store-1',
    )..start();
    await session.signIn(email: 'owner@test.com', password: 'secret');
    expect(session.status, AuthSessionStatus.failure);
    expect(session.membership, isNull);
    session.dispose();
    await auth.dispose();
  });

}

class _FakeAuth implements AuthRepository {
  static const user = AuthenticatedUser(id: 'user-1', email: 'owner@test.com');
  final _updates = StreamController<AuthenticatedUser?>.broadcast();
  AuthenticatedUser? _current;

  @override
  AuthenticatedUser? get currentUser => _current;

  @override
  Stream<AuthenticatedUser?> authStateChanges() => _updates.stream;

  @override
  Future<Result<AuthenticatedUser>> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    _current = user;
    return const Success<AuthenticatedUser>(user);
  }

  @override
  Future<Result<AuthenticatedUser>> createUserWithEmailPassword({
    required String email,
    required String password,
    String? displayName,
  }) async => const Success<AuthenticatedUser>(user);

  @override
  Future<Result<void>> sendPasswordResetEmail({
    required String email,
  }) async => const Success<void>(null);

  @override
  Future<Result<void>> signOut() async {
    _current = null;
    return const Success<void>(null);
  }

  Future<void> dispose() => _updates.close();
}

class _FakeMembership
    implements StoreMembershipRepository, StoreMembershipWatcher {
  final _watchers = <String, StreamController<Result<StoreMembership>>>{};

  StreamController<Result<StoreMembership>> _watcher(String storeId) =>
      _watchers.putIfAbsent(
        storeId,
        () => StreamController<Result<StoreMembership>>.broadcast(sync: true),
      );

  void emit(String storeId, Result<StoreMembership> membership) =>
      _watcher(storeId).add(membership);

  @override
  Future<Result<StoreMembership>> getMembership({
    required StoreContext context,
  }) async => Success<StoreMembership>(
        StoreMembership(
          storeId: context.storeId,
          userId: context.userId,
          role: StoreRole.owner,
        ),
      );

  @override
  Stream<Result<StoreMembership>> watchMembership({
    required StoreContext context,
  }) => _watcher(context.storeId).stream;

  Future<void> dispose() async {
    for (final controller in _watchers.values) {
      await controller.close();
    }
  }
}

class _FakeOnboarding implements StoreOnboardingRepository {
  String? _selected;

  @override
  Future<Result<String?>> getSelectedStoreId({
    required String userId,
  }) async => Success<String?>(_selected);

  @override
  Future<Result<String>> createStore({required String name}) async =>
      const Success<String>('store-1');

  @override
  Future<Result<String>> selectStore({required String storeId}) async {
    _selected = storeId;
    return Success<String>(storeId);
  }
}

class _DelayedAuth extends _FakeAuth {
  final _result = Completer<Result<AuthenticatedUser>>();

  @override
  Future<Result<AuthenticatedUser>> signInWithEmailPassword({
    required String email,
    required String password,
  }) => _result.future;

  void completeSignIn() =>
      _result.complete(const Success<AuthenticatedUser>(_FakeAuth.user));
}

class _WrongMembership implements StoreMembershipRepository {
  @override
  Future<Result<StoreMembership>> getMembership({
    required StoreContext context,
  }) async => const Success<StoreMembership>(
        StoreMembership(
          storeId: 'foreign-tenant',
          userId: 'user-1',
          role: StoreRole.owner,
        ),
      );
}
