import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../core/config/app_runtime_config.dart';
import '../features/accounting/data/repositories/firestore_accounting_query_repository.dart';
import '../features/auth/application/auth_session_controller.dart';
import '../features/auth/data/repositories/firebase_auth_repository.dart';
import '../features/auth/data/repositories/firestore_store_membership_repository.dart';
import '../features/inventory/data/repositories/firestore_product_repository.dart';
import 'app_dependencies.dart';

abstract final class AppBootstrap {
  static Future<AppDependencies> initialize({
    AppRuntimeConfig? config,
  }) async {
    final runtime = config ?? AppRuntimeConfig.fromEnvironment();
    if (!runtime.useFirebase) {
      return AppDependencies(runtime: runtime);
    }

    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }

    final firestore = FirebaseFirestore.instance;
    final session = AuthSessionController(
      authRepository: FirebaseAuthRepository(
        auth: FirebaseAuth.instance,
      ),
      membershipRepository: FirestoreStoreMembershipRepository(
        firestore: firestore,
      ),
      storeId: runtime.storeId,
    );

    session.start();

    return AppDependencies(
      runtime: runtime,
      authSession: session,
      accountingQueryRepository:
          FirestoreAccountingQueryRepository(firestore: firestore),
      productRepository: FirestoreProductRepository(
        firestore: firestore,
      ),
    );
  }
}
