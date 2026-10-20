import '../core/config/app_runtime_config.dart';
import '../features/accounting/domain/repositories/accounting_query_repository.dart';
import '../features/offers/domain/repositories/offer_repository.dart';
import '../features/accounting/domain/repositories/accounting_repository.dart';
import '../features/accounting_audit/domain/repositories/accounting_audit_repository.dart';
import '../features/categories/domain/repositories/category_repository.dart';
import '../features/cheques/domain/repositories/cheque_repository.dart';
import '../features/auth/application/auth_session_controller.dart';
import '../features/inventory/domain/repositories/inventory_repository.dart';
import '../features/inventory/domain/repositories/product_repository.dart';
import '../features/sales/domain/repositories/sale_repository.dart';
import '../features/purchases/domain/repositories/purchase_repository.dart';
import '../features/reports/domain/repositories/reports_repository.dart';
import '../features/reports/domain/services/report_document_builder.dart';
import '../features/settings/domain/repositories/settings_repository.dart';
import '../features/repairs/domain/repositories/repair_repository.dart';
import '../features/repairs/domain/services/repair_document_builder.dart';
import '../features/purchase_orders/domain/repositories/purchase_order_repository.dart';
import '../features/expenses/domain/repositories/expense_repository.dart';
import '../features/payments/domain/repositories/party_payment_repository.dart';
import '../features/parties/domain/repositories/party_ledger_repository.dart';
import '../features/parties/domain/repositories/party_repository.dart';
import '../features/transfers/domain/repositories/account_transfer_repository.dart';

class AppDependencies {
  const AppDependencies({
    required this.runtime,
    this.authSession,
    this.accountingRepository,
    this.accountingAuditRepository,
    this.categoryRepository,
    this.chequeRepository,
    this.accountingQueryRepository,
    this.inventoryRepository,
    this.productRepository,
    this.saleRepository,
    this.purchaseRepository,
    this.purchaseOrderRepository,
    this.offerRepository,
    this.expenseRepository,
    this.partyPaymentRepository,
    this.partyRepository,
    this.partyLedgerRepository,
    this.accountTransferRepository,
    this.repairRepository,
    this.repairDocumentBuilder,
    this.reportsRepository,
    this.reportDocumentBuilder,
    this.settingsRepository,
  });

  final AppRuntimeConfig runtime;
  final AuthSessionController? authSession;
  final AccountingRepository? accountingRepository;
  final AccountingAuditRepository? accountingAuditRepository;
  final CategoryRepository? categoryRepository;
  final ChequeRepository? chequeRepository;
  final AccountingQueryRepository? accountingQueryRepository;
  final InventoryRepository? inventoryRepository;
  final ProductRepository? productRepository;
  final SaleRepository? saleRepository;
  final PurchaseRepository? purchaseRepository;
  final PurchaseOrderRepository? purchaseOrderRepository;
  final OfferRepository? offerRepository;
  final ExpenseRepository? expenseRepository;
  final PartyPaymentRepository? partyPaymentRepository;
  final PartyRepository? partyRepository;
  final PartyLedgerRepository? partyLedgerRepository;
  final AccountTransferRepository? accountTransferRepository;
  final RepairRepository? repairRepository;
  final RepairDocumentBuilder? repairDocumentBuilder;
  final ReportsRepository? reportsRepository;
  final ReportDocumentBuilder? reportDocumentBuilder;
  final SettingsRepository? settingsRepository;

  bool get hasFirebaseSession => authSession != null;
}
