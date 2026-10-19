import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../domain/entities/authenticated_user.dart';
import '../domain/entities/store_membership.dart';
import '../domain/repositories/auth_repository.dart';
import '../domain/repositories/store_membership_repository.dart';

enum AuthSessionStatus {
  signedOut,
  signingIn,
  loadingMembership,
  ready,
  storeNotConfigured,
  failure,
}

class AuthSessionController extends ChangeNotifier {
  AuthSessionController({
    required AuthRepository authRepository,
    required StoreMembershipRepository membershipRepository,
    required String storeId,
  })  : _authRepository = authRepository,
        _membershipRepository = membershipRepository,
        _storeId = storeId.trim();

  final AuthRepository _authRepository;
  final StoreMembershipRepository _membershipRepository;
  final String _storeId;

  StreamSubscription<AuthenticatedUser?>? _authSubscription;
  AuthSessionStatus _status = AuthSessionStatus.signedOut;
  AuthenticatedUser? _user;
  StoreMembership? _membership;
  String? _errorMessage;

  AuthSessionStatus get status => _status;
  AuthenticatedUser? get user => _user;
  StoreMembership? get membership => _membership;
  String? get errorMessage => _errorMessage;
  bool get isBusy =>
      _status == AuthSessionStatus.signingIn ||
      _status == AuthSessionStatus.loadingMembership;

  void start() {
    if (_authSubscription != null) {
      return;
    }

    _authSubscription = _authRepository.authStateChanges().listen(
      _handleUser,
      onError: (Object error, _) {
        _setFailure(error.toString());
      },
    );

    final currentUser = _authRepository.currentUser;
    if (currentUser != null) {
      unawaited(_handleUser(currentUser));
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    _setState(
      status: AuthSessionStatus.signingIn,
      errorMessage: null,
    );

    final result = await _authRepository.signInWithEmailPassword(
      email: email,
      password: password,
    );

    if (result is FailureResult<AuthenticatedUser>) {
      _setFailure(result.failure.message);
      return;
    }

    if (result is Success<AuthenticatedUser>) {
      await _handleUser(result.value);
    }
  }

  Future<void> signOut() async {
    _setState(
      status: AuthSessionStatus.signingIn,
      errorMessage: null,
    );
    final result = await _authRepository.signOut();
    if (result is FailureResult<void>) {
      _setFailure(result.failure.message);
      return;
    }

    _user = null;
    _membership = null;
    _setState(status: AuthSessionStatus.signedOut);
  }

  Future<void> reloadMembership() async {
    final user = _user;
    if (user == null) {
      _setState(status: AuthSessionStatus.signedOut);
      return;
    }
    await _handleUser(user);
  }

  Future<void> _handleUser(AuthenticatedUser? user) async {
    _user = user;
    _membership = null;
    _errorMessage = null;

    if (user == null) {
      _setState(status: AuthSessionStatus.signedOut);
      return;
    }

    if (_storeId.isEmpty) {
      _setState(status: AuthSessionStatus.storeNotConfigured);
      return;
    }

    _setState(status: AuthSessionStatus.loadingMembership);
    final result = await _membershipRepository.getMembership(
      context: StoreContext(
        storeId: _storeId,
        userId: user.id,
      ),
    );

    if (result is FailureResult<StoreMembership>) {
      _setFailure(result.failure.message);
      return;
    }

    if (result is Success<StoreMembership>) {
      _membership = result.value;
      _setState(status: AuthSessionStatus.ready);
    }
  }

  void _setFailure(String message) {
    _setState(
      status: AuthSessionStatus.failure,
      errorMessage: message,
    );
  }

  void _setState({
    required AuthSessionStatus status,
    String? errorMessage,
  }) {
    _status = status;
    _errorMessage = errorMessage;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }
}
