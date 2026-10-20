import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../core/config/app_runtime_config.dart';
import '../features/accounting/data/repositories/firestore_accounting_query_repository.dart';
import '../features/accounting/data/repositories/firestore_accounting_repository.dart';
import '../features/accounting_audit/data/repositories/firestore_accounting_audit_repository.dart';
import '../features/categories/data/repositories/firestore_category_repository.dart';
import '../features/cheques/data/repositories/firestore_cheque_repository.dart';
import '../features/auth/application/auth_session_controller.dart';
import '../features/auth/data/repositories/firebase_auth_repository.dart';
import '../features/auth/data/repositories/firestore_store_membership_repository.dart';
import '../features/inventory/data/repositories/firestore_inventory_repository.dart';
import '../features/inventory/data/repositories/firestore_product_repository.dart';
import '../features/sales/data/repositories/firestore_sale_repository.dart';
import '../features/purchases/data/repositories/firestore_purchase_repository.dart';
import '../features/repairs/data/repositories/firestore_repair_repository.dart';
import '../features/purchase_orders/data/repositories/firestore_purchase_order_repository.dart';
import '../features/reports/data/repositories/firestore_reports_repository.dart';
import '../features/reports/data/exporters/pdf_report_document_builder.dart';
import '../features/settings/data/repositories/firestore_settings_repository.dart';
import '../features/offers/data/repositories/firestore_offer_repository.dart';
import '../features/expenses/data/repositories/firestore_expense_repository.dart';
import '../features/payments/data/repositories/firestore_party_payment_repository.dart';
import '../features/parties/data/repositories/firestore_party_ledger_repository.dart';
import '../features/parties/data/repositories/firestore_party_repository.dart';
import '../features/transfers/data/repositories/firestore_account_transfer_repository.dart';
import '../infrastructure/queue/firestore_command_queue_repository.dart';
import 'app_dependencies.dart';

abstract final class AppBootstrap {
  static Future<AppDependencies> initialize({AppRuntimeConfig? config}) async {
    final runtime = config ?? AppRuntimeConfig.fromEnvironment();
    if (!runtime.useFirebase) {
      return AppDependencies(
        runtime: runtime,
        reportDocumentBuilder: PdfReportDocumentBuilder(),
      );
    }

    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }

    final firestore = FirebaseFirestore.instance;
    final functions = FirebaseFunctions.instanceFor(region: 'europe-west1');
    final commandQueue = FirestoreCommandQueueRepository(firestore: firestore);
    final session = AuthSessionController(
      authRepository: FirebaseAuthRepository(auth: FirebaseAuth.instance),
      membershipRepository: FirestoreStoreMembershipRepository(
        firestore: firestore,
      ),
      storeId: runtime.storeId,
    );

    session.start();

    return AppDependencies(
      runtime: runtime,
      authSession: session,
      accountingAuditRepository: FirestoreAccountingAuditRepository(
        functions: functions,
      ),
      accountingRepository: FirestoreAccountingRepository(
        firestore: firestore,
        functions: functions,
        commandQueue: commandQueue,
      ),
      categoryRepository: FirestoreCategoryRepository(firestore: firestore),
      chequeRepository: FirestoreChequeRepository(
        firestore: firestore,
        functions: functions,
        commandQueue: commandQueue,
      ),
      accountingQueryRepository: FirestoreAccountingQueryRepository(
        firestore: firestore,
      ),
      inventoryRepository: FirestoreInventoryRepository(
        firestore: firestore,
        functions: functions,
        commandQueue: commandQueue,
      ),
      productRepository: FirestoreProductRepository(firestore: firestore),
      saleRepository: FirestoreSaleRepository(
        functions: functions,
        commandQueue: commandQueue,
      ),
      purchaseRepository: FirestorePurchaseRepository(
        functions: functions,
        commandQueue: commandQueue,
      ),
      purchaseOrderRepository: FirestorePurchaseOrderRepository(
        firestore: firestore,
        functions: functions,
        commandQueue: commandQueue,
      ),
      offerRepository: FirestoreOfferRepository(
        firestore: firestore,
        functions: functions,
        commandQueue: commandQueue,
      ),
      expenseRepository: FirestoreExpenseRepository(
        functions: functions,
        commandQueue: commandQueue,
      ),
      partyPaymentRepository: FirestorePartyPaymentRepository(
        functions: functions,
        commandQueue: commandQueue,
      ),
      partyRepository: FirestorePartyRepository(firestore: firestore),
      partyLedgerRepository: FirestorePartyLedgerRepository(
        firestore: firestore,
      ),
      accountTransferRepository: FirestoreAccountTransferRepository(
        functions: functions,
        commandQueue: commandQueue,
      ),
      repairRepository: FirestoreRepairRepository(
        firestore: firestore,
        functions: functions,
        commandQueue: commandQueue,
      ),
      reportsRepository: FirestoreReportsRepository(firestore: firestore),
      reportDocumentBuilder: PdfReportDocumentBuilder(),
      settingsRepository: FirestoreSettingsRepository(firestore: firestore),
    );
  }
}