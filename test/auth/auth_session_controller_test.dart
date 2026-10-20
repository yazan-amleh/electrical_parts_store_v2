import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:electrical_parts_store_v2/core/errors/failure.dart';
import 'package:electrical_parts_store_v2/core/result/result.dart';
import 'package:electrical_parts_store_v2/core/tenancy/store_context.dart';
import 'package:electrical_parts_store_v2/features/auth/application/auth_session_controller.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/authenticated_user.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/entities/store_membership.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/enums/store_role.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/repositories/auth_repository.dart';
import 'package:electrical_parts_store_v2/features/auth/domain/repositories/store_membership_repository.dart';

void main() {
  const user = AuthenticatedUser(id: 'user-1', email: 'user@example.com');
  const membership = StoreMembership(
    storeId: 'store-1',
    userId: 'user-1',
    role: StoreRole.accountant,
  );

  test('loads membership before exposing a ready session', () async {
    final auth = _FakeAuthRepository();
    final memberships = _FakeMembershipRepository();
    final controller = AuthSessionController(
      authRepository: auth,
      membershipRepository: memberships,
      storeId: 'store-1',
    )..start();

    expect(controller.status, AuthSessionStatus.signedOut);

    await controller.signIn(email: user.email, password: 'password');

    expect(controller.status, AuthSessionStatus.ready);
    expect(controller.user, user);
    expect(controller.membership, membership);
    expect(memberships.lastContext?.storeId, 'store-1');

    controller.dispose();
    await auth.dispose();
  });

  test('does not claim ready when the store is not configured', () async {
    final auth = _FakeAuthRepository();
    final controller = AuthSessionController(
      authRepository: auth,
      membershipRepository: _FakeMembershipRepository(),
      storeId: '',
    )..start();

    await controller.signIn(email: user.email, password: 'password');

    expect(controller.status, AuthSessionStatus.storeNotConfigured);
    expect(controller.membership, isNull);

    controller.dispose();
    await auth.dispose();
  });

  test('surfaces membership authorization failures', () async {
    final auth = _FakeAuthRepository();
    final controller = AuthSessionController(
      authRepository: auth,
      membershipRepository: _FakeMembershipRepository(
        result: const FailureResult<StoreMembership>(
          AuthorizationFailure('Not a member.'),
        ),
      ),
      storeId: 'store-1',
    )..start();

    await controller.signIn(email: user.email, password: 'password');

    expect(controller.status, AuthSessionStatus.failure);
    expect(controller.errorMessage, 'Not a member.');

    controller.dispose();
    await auth.dispose();
  });
}

class _FakeAuthRepository implements AuthRepository {
  final _changes = StreamController<AuthenticatedUser?>.broadcast();
  AuthenticatedUser? _currentUser;

  @override
  AuthenticatedUser? get currentUser => _currentUser;

  @override
  Stream<AuthenticatedUser?> authStateChanges() => _changes.stream;

  @override
  Future<Result<AuthenticatedUser>> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    _currentUser = const AuthenticatedUser(
      id: 'user-1',
      email: 'user@example.com',
    );
    return Success<AuthenticatedUser>(_currentUser!);
  }

  @override
  Future<Result<void>> signOut() async {
    _currentUser = null;
    return const Success<void>(null);
  }

  Future<void> dispose() => _changes.close();
}

class _FakeMembershipRepository implements StoreMembershipRepository {
  _FakeMembershipRepository({
    this.result = const Success<StoreMembership>(
      StoreMembership(
        storeId: 'store-1',
        userId: 'user-1',
        role: StoreRole.accountant,
      ),
    ),
  });

  final Result<StoreMembership> result;
  StoreContext? lastContext;

  @override
  Future<Result<StoreMembership>> getMembership({
    required StoreContext context,
  }) async {
    lastContext = context;
    return result;
  }
}
