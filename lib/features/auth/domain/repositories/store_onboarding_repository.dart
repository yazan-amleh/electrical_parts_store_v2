import '../../../../core/result/result.dart';

/// Resolves a previously selected store and performs authenticated, server-
/// authorized onboarding commands. Mutations must never bypass Cloud Functions.
abstract interface class StoreOnboardingRepository {
  Future<Result<String?>> getSelectedStoreId({required String userId});

  Future<Result<String>> createStore({required String name});

  Future<Result<String>> selectStore({required String storeId});
}
