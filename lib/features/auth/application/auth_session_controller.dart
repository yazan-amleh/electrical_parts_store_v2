import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/errors/failure.dart';
import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../domain/entities/authenticated_user.dart';
import '../domain/entities/store_membership.dart';
import '../domain/repositories/auth_repository.dart';
import '../domain/repositories/store_membership_repository.dart';
import '../domain/repositories/store_onboarding_repository.dart';

enum AuthSessionStatus {
  signedOut,
  signingIn,
  loadingMembership,
  ready,
  storeNotConfigured,
  storeSetupRequired,
  creatingStore,
  failure,
}

class AuthSessionController extends ChangeNotifier {
  AuthSessionController({
    required AuthRepository authRepository,
    required StoreMembershipRepository membershipRepository,
    StoreOnboardingRepository? onboardingRepository,
    required String storeId,
  })  : _authRepository = authRepository,
        _membershipRepository = membershipRepository,
        _onboardingRepository = onboardingRepository,
        _configuredStoreId = storeId.trim(),
        _storeId = storeId.trim();

  final AuthRepository _authRepository;
  final StoreMembershipRepository _membershipRepository;
  final StoreOnboardingRepository? _onboardingRepository;
  final String _configuredStoreId;
  String _storeId;

  StreamSubscription<AuthenticatedUser?>? _authSubscription;
  StreamSubscription<Result<StoreMembership>>? _membershipSubscription;
  AuthSessionStatus _status = AuthSessionStatus.signedOut;
  AuthenticatedUser? _user;
  StoreMembership? _membership;
  String? _errorMessage;

  AuthSessionStatus get status => _status;
  AuthenticatedUser? get user => _user;
  StoreMembership? get membership => _membership;
  String? get errorMessage => _errorMessage;
  String get storeId => _storeId;
  bool get isBusy =>
      _status == AuthSessionStatus.signingIn ||
      _status == AuthSessionStatus.loadingMembership ||
      _status == AuthSessionStatus.creatingStore;

  int _sessionRequestId = 0;

  void start() {
    if (_authSubscription != null) {
      return;
    }

    _authSubscription = _authRepository.authStateChanges().listen(
      _handleUser,
      onError: (Object error, _) {
        ++_sessionRequestId;
        _stopMembershipWatch();
        _membership = null;
        _setFailure(error.toString());
      },
    );

    final currentUser = _authRepository.currentUser;
    if (currentUser != null) {
      unawaited(_handleUser(currentUser));
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    final operationId = ++_sessionRequestId;
    _stopMembershipWatch();
    _membership = null;
    _setState(status: AuthSessionStatus.signingIn, errorMessage: null);

    final result = await _authRepository.signInWithEmailPassword(
      email: email,
      password: password,
    );

    if (operationId != _sessionRequestId) return;

    if (result is FailureResult<AuthenticatedUser>) {
      _setAuthFailure(result.failure.message);
      return;
    }

    if (result is Success<AuthenticatedUser>) {
      await _handleUser(result.value);
    }
  }

  Future<void> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final operationId = ++_sessionRequestId;
    _stopMembershipWatch();
    _membership = null;
    _setState(status: AuthSessionStatus.signingIn, errorMessage: null);

    final result = await _authRepository.createUserWithEmailPassword(
      email: email,
      password: password,
      displayName: displayName,
    );

    if (operationId != _sessionRequestId) return;

    if (result is FailureResult<AuthenticatedUser>) {
      _setAuthFailure(result.failure.message);
      return;
    }

    if (result is Success<AuthenticatedUser>) {
      await _handleUser(result.value);
    }
  }

  Future<Result<void>> sendPasswordResetEmail({
    required String email,
  }) {
    return _authRepository.sendPasswordResetEmail(email: email);
  }

  Future<void> signOut() async {
    _stopMembershipWatch();
    _membership = null;
    _sessionRequestId += 1;
    _setState(status: AuthSessionStatus.signingIn, errorMessage: null);
    final result = await _authRepository.signOut();
    if (result is FailureResult<void>) {
      _setFailure(result.failure.message);
      return;
    }

    _user = null;
    _membership = null;
    _storeId = _configuredStoreId;
    _setState(status: AuthSessionStatus.signedOut);
  }

  Future<void> reloadMembership() async {
    final user = _user;
    if (user == null) {
      _storeId = _configuredStoreId;
      _setState(status: AuthSessionStatus.signedOut);
      return;
    }
    await _handleUser(user);
  }

  void openStoreSetup() {
    if (_user != null && _onboardingRepository != null && !isBusy) {
      ++_sessionRequestId;
      _stopMembershipWatch();
      _membership = null;
      _setState(
        status: AuthSessionStatus.storeSetupRequired,
        errorMessage: null,
      );
    }
  }

  /// Creates a fresh, server-generated V2 store with the current user as owner.
  Future<void> createStore({required String name}) async {
    final onboarding = _onboardingRepository;
    final user = _user;
    if (onboarding == null || user == null) {
      _setFailure('يرجى تسجيل الدخول قبل إنشاء متجر.');
      return;
    }
    _stopMembershipWatch();
    _membership = null;
    final requestId = ++_sessionRequestId;
    _setState(status: AuthSessionStatus.creatingStore, errorMessage: null);
    final result = await onboarding.createStore(name: name);
    if (requestId != _sessionRequestId || _user?.id != user.id) return;
    if (result is FailureResult<String>) {
      _setState(
        status: AuthSessionStatus.storeSetupRequired,
        errorMessage: result.failure.message,
      );
      return;
    }
    if (result is Success<String>) {
      _storeId = result.value;
      await _handleUser(user);
    }
  }

  /// Selects an existing store only after the server confirms active membership.
  Future<void> selectStore({required String storeId}) async {
    final onboarding = _onboardingRepository;
    final user = _user;
    if (onboarding == null || user == null) {
      _setFailure('يرجى تسجيل الدخول قبل اختيار متجر.');
      return;
    }
    _stopMembershipWatch();
    _membership = null;
    final requestId = ++_sessionRequestId;
    _setState(status: AuthSessionStatus.loadingMembership, errorMessage: null);
    final result = await onboarding.selectStore(storeId: storeId);
    if (requestId != _sessionRequestId || _user?.id != user.id) return;
    if (result is FailureResult<String>) {
      _setState(
        status: AuthSessionStatus.storeSetupRequired,
        errorMessage: result.failure.message,
      );
      return;
    }
    if (result is Success<String>) {
      _storeId = result.value;
      await _handleUser(user);
    }
  }

  Future<void> _handleUser(AuthenticatedUser? user) async {
    final requestId = ++_sessionRequestId;
    _stopMembershipWatch();
    _user = user;
    _membership = null;
    _errorMessage = null;

    if (user == null) {
      _setState(status: AuthSessionStatus.signedOut);
      return;
    }

    _setState(status: AuthSessionStatus.loadingMembership);
    final onboarding = _onboardingRepository;
    if (onboarding != null) {
      final preferred = await onboarding.getSelectedStoreId(userId: user.id);
      if (requestId != _sessionRequestId) return;
      if (preferred is FailureResult<String?>) {
        _setFailure(preferred.failure.message);
        return;
      }
      if (preferred is Success<String?>) {
        _storeId = preferred.value ?? _configuredStoreId;
      }
    }

    if (_storeId.isEmpty || _storeId.contains('/')) {
      _setState(
        status: onboarding == null
            ? AuthSessionStatus.storeNotConfigured
            : AuthSessionStatus.storeSetupRequired,
      );
      return;
    }

    final result = await _membershipRepository.getMembership(
      context: StoreContext(storeId: _storeId, userId: user.id),
    );

    if (requestId != _sessionRequestId) {
      return;
    }

    if (result is FailureResult<StoreMembership>) {
      if (onboarding != null &&
          result.failure is StoreMembershipNotFoundFailure) {
        _setState(
          status: AuthSessionStatus.storeSetupRequired,
          errorMessage: null,
        );
      } else {
        _setFailure(result.failure.message);
      }
      return;
    }

    if (result is Success<StoreMembership>) {
      if (!_matchesSession(result.value, user, _storeId)) {
        _setFailure('تم استلام عضوية لا تطابق حساب المستخدم أو المتجر.');
        return;
      }
      _membership = result.value;
      _setState(status: AuthSessionStatus.ready);
      _startMembershipWatch(
        requestId: requestId,
        user: user,
        storeId: _storeId,
      );
    }
  }

  bool _matchesSession(
    StoreMembership membership,
    AuthenticatedUser user,
    String storeId,
  ) =>
      membership.storeId == storeId &&
      membership.userId == user.id &&
      membership.canAccessStore;

  void _startMembershipWatch({
    required int requestId,
    required AuthenticatedUser user,
    required String storeId,
  }) {
    final StoreMembershipWatcher? watcher =
        _membershipRepository is StoreMembershipWatcher
            ? _membershipRepository as StoreMembershipWatcher
            : null;
    if (watcher == null) return;

    _membershipSubscription = watcher
        .watchMembership(
      context: StoreContext(storeId: storeId, userId: user.id),
    )
        .listen(
      (Result<StoreMembership> result) {
        if (requestId != _sessionRequestId ||
            _user?.id != user.id ||
            _storeId != storeId) {
          return;
        }
        if (result is FailureResult<StoreMembership>) {
          _membership = null;
          if (result.failure is StoreMembershipNotFoundFailure ||
              result.failure is AuthorizationFailure) {
            _stopMembershipWatch();
            _setState(
              status: AuthSessionStatus.storeSetupRequired,
              errorMessage: result.failure.message,
            );
          } else {
            _setFailure(result.failure.message);
          }
          return;
        }

        if (result is Success<StoreMembership>) {
          if (!_matchesSession(result.value, user, storeId)) {
            _membership = null;
            _stopMembershipWatch();
            _setState(
              status: AuthSessionStatus.storeSetupRequired,
              errorMessage: 'تم إلغاء صلاحية الوصول إلى المتجر.',
            );
            return;
          }
          final previous = _membership;
          _membership = result.value;
          if (_status != AuthSessionStatus.ready ||
              previous?.role != result.value.role) {
            _setState(status: AuthSessionStatus.ready);
          }
        }
      },
      onError: (Object error, StackTrace stack) {
        if (requestId != _sessionRequestId ||
            _user?.id != user.id ||
            _storeId != storeId) {
          return;
        }
        _membership = null;
        _setFailure(
            'تعذر متابعة صلاحيات المتجر. تحقق من الاتصال وأعد المحاولة.');
      },
    );
  }

  void _stopMembershipWatch() {
    final subscription = _membershipSubscription;
    _membershipSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
  }

  void _setFailure(String message) {
    _setState(status: AuthSessionStatus.failure, errorMessage: message);
  }

  void _setAuthFailure(String message) {
    _setState(status: AuthSessionStatus.signedOut, errorMessage: message);
  }

  void _setState({required AuthSessionStatus status, String? errorMessage}) {
    _status = status;
    _errorMessage = errorMessage;
    notifyListeners();
  }

  @override
  void dispose() {
    ++_sessionRequestId;
    _stopMembershipWatch();
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }
}
