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
import 'package:electrical_parts_store_v2/features/auth/domain/repositories/store_onboarding_repository.dart';

void main() {
  test('new account enters setup and creates an owner store', () async {
    final auth = _AuthFake();
    final onboarding = _OnboardingFake();
    final memberships = _MembershipFake();
    final controller = AuthSessionController(
      authRepository: auth,
      membershipRepository: memberships,
      onboardingRepository: onboarding,
      storeId: 'legacy-dev-store',
    )..start();

    await controller.register(
      email: 'owner@example.com',
      password: 'password',
    );
    expect(controller.status, AuthSessionStatus.storeSetupRequired);
    expect(controller.membership, isNull);
    await controller.createStore(name: 'Electrical Shop');
    expect(controller.status, AuthSessionStatus.ready);
    expect(controller.storeId, 'new-store');
    expect(controller.membership!.role, StoreRole.owner);
    expect(memberships.lastStoreId, 'new-store');

    await controller.signOut();
    expect(controller.status, AuthSessionStatus.signedOut);
    controller.dispose();
    await auth.dispose();
  });

  test('restores selected store before checking membership', () async {
    final auth = _AuthFake();
    final onboarding = _OnboardingFake()..selectedStore = 'new-store';
    final memberships = _MembershipFake();
    final controller = AuthSessionController(
      authRepository: auth,
      membershipRepository: memberships,
      onboardingRepository: onboarding,
      storeId: 'legacy-dev-store',
    )..start();
    await controller.signIn(
      email: 'owner@example.com',
      password: 'password',
    );
    expect(controller.status, AuthSessionStatus.ready);
    expect(memberships.lastStoreId, 'new-store');
    controller.dispose();
    await auth.dispose();
  });

  test('denied selection never marks the session ready', () async {
    final auth = _AuthFake();
    final onboarding = _OnboardingFake()..allowSelection = false;
    final controller = AuthSessionController(
      authRepository: auth,
      membershipRepository: _MembershipFake(),
      onboardingRepository: onboarding,
      storeId: 'legacy-dev-store',
    )..start();
    await controller.signIn(email: 'owner@example.com', password: 'password');
    expect(controller.status, AuthSessionStatus.storeSetupRequired);
    await controller.selectStore(storeId: 'foreign-store');
    expect(controller.status, AuthSessionStatus.storeSetupRequired);
    expect(controller.membership, isNull);
    expect(controller.errorMessage, isNotNull);
    controller.dispose();
    await auth.dispose();
  });

  test('transport failures do not turn into onboarding permission', () async {
    final auth = _AuthFake();
    final onboarding = _OnboardingFake()..lookupFails = true;
    final controller = AuthSessionController(
      authRepository: auth,
      membershipRepository: _MembershipFake(),
      onboardingRepository: onboarding,
      storeId: 'legacy-dev-store',
    )..start();
    await controller.signIn(email: 'owner@example.com', password: 'password');
    expect(controller.status, AuthSessionStatus.failure);
    expect(controller.membership, isNull);
    controller.dispose();
    await auth.dispose();
  });
}

class _AuthFake implements AuthRepository {
  final _changes = StreamController<AuthenticatedUser?>.broadcast();
  static const owner = AuthenticatedUser(
    id: 'owner-id',
    email: 'owner@example.com',
  );
  AuthenticatedUser? _user;

  @override
  AuthenticatedUser? get currentUser => _user;

  @override
  Stream<AuthenticatedUser?> authStateChanges() => _changes.stream;

  @override
  Future<Result<AuthenticatedUser>> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    _user = owner;
    return const Success<AuthenticatedUser>(owner);
  }

  @override
  Future<Result<AuthenticatedUser>> createUserWithEmailPassword({
    required String email,
    required String password,
    String? displayName,
  }) async {
    _user = owner;
    return const Success<AuthenticatedUser>(owner);
  }

  @override
  Future<Result<void>> sendPasswordResetEmail({
    required String email,
  }) async => const Success<void>(null);

  @override
  Future<Result<void>> signOut() async {
    _user = null;
    return const Success<void>(null);
  }

  Future<void> dispose() => _changes.close();
}

class _MembershipFake implements StoreMembershipRepository {
  String? lastStoreId;

  @override
  Future<Result<StoreMembership>> getMembership({
    required StoreContext context,
  }) async {
    lastStoreId = context.storeId;
    if (context.storeId != 'new-store') {
      return const FailureResult<StoreMembership>(
        StoreMembershipNotFoundFailure('No membership.'),
      );
    }
    return Success<StoreMembership>(
      StoreMembership(
        storeId: context.storeId,
        userId: context.userId,
        role: StoreRole.owner,
      ),
    );
  }
}

class _OnboardingFake implements StoreOnboardingRepository {
  String? selectedStore;
  bool allowSelection = true;
  bool lookupFails = false;

  @override
  Future<Result<String?>> getSelectedStoreId({
    required String userId,
  }) async {
    if (lookupFails) {
      return const FailureResult<String?>(
        InfrastructureFailure('No connection.'),
      );
    }
    return Success<String?>(selectedStore);
  }

  @override
  Future<Result<String>> createStore({
    required String name,
  }) async {
    selectedStore = 'new-store';
    return const Success<String>('new-store');
  }

  @override
  Future<Result<String>> selectStore({
    required String storeId,
  }) async {
    if (!allowSelection) {
      return const FailureResult<String>(
        AuthorizationFailure('Not a member.'),
      );
    }
    selectedStore = storeId;
    return Success<String>(storeId);
  }
}
