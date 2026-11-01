# Screen/action parity ledger — audit baseline

**Status rule:** present in source != visually matched != functionally tested. No screen is accepted until every button, navigation path, empty/loading/error state, RTL/responsive layout and relevant PDF/print output is verified.

| V1 source screens (representative, not exclusive) | V2 destination | Code exists | V1 design verified | Real Firebase workflow verified | Notes |
| --- | --- | --- | --- | --- | --- |
| `views/screens/auth/login_screen.dart`, `auth/register_screen.dart`, `auth/reset_password_screen.dart` | `features/auth/presentation/{login,register,reset_password}_page.dart` | Yes | **NO** | **NO** | 661-line V1 login vs 212-line V2 login; preserve V1 UI while replacing its controller |
| `views/screens/home_screen.dart`, `views/widgets/custom_drawer.dart` | `features/shell/presentation/app_shell_page.dart` | Yes | **NO** | **NO** | Drawer, bottom navigation, role filtering, transitions need item-by-item comparison |
| `views/screens/dashboard_screen.dart`, `quick_stats_screen.dart` | `features/dashboard/presentation/dashboard_page.dart` | Yes | **NO** | **NO** | Card layout and analytics |
| `views/screens/products_management_screen.dart`, `all_products_screen.dart`, `add_edit_product_screen.dart`, `product_details_screen.dart` | `features/inventory/presentation/products_page.dart`, `product_editor_dialog.dart` | Yes | **NO** | **NO** | Screen/action granularity pending |
| `views/screens/categories_screen.dart`, `add_edit_category_screen.dart`, `category_details_screen.dart` | `features/categories/presentation/categories_page.dart` | Yes | **NO** | **NO** | Include print and nested category navigation |
| `views/screens/inventory_management_screen*.dart` | `features/inventory/presentation/inventory_movements_page.dart` | Yes | **NO** | **NO** | Stock history/value path is hardened; stock-only sale/purchase-return posting is disabled pending a real financial reversal workflow. Manual opening/adjustment GL policy remains open. |
| `views/screens/sales_screen.dart`, `add_sale_screen.dart`, `sale_details_screen.dart`, `cart_screen.dart`, `flexible_sales_screen.dart` | `features/sales/presentation/sales_page.dart` | Yes | **NO** | **NO** | Standard, grouped and flexible sale workflows |
| `views/screens/purchase_orders_screen.dart`, `add_purchase_order_screen.dart` | `features/purchase_orders/presentation/purchase_orders_page.dart` | Yes | **NO** | **NO** | Partial receipt and cancellation |
| `financial_management/views/screens/purchases_screen.dart` | `features/purchases/presentation/purchases_page.dart` | Yes | **NO** | **NO** | Purchase posting and settlement |
| `views/screens/customers_screen.dart`, `suppliers_screen.dart`, `customer_details_screen.dart` | `features/parties/presentation/party_directory_page.dart`, `party_ledger_page.dart` | Yes | **NO** | **NO** | Filters, balances, credit/debt details |
| `views/screens/payments_screen.dart`, `add_payment_screen.dart`, `cheque_payment_details_screen.dart` | `features/payments/presentation/party_payments_page.dart`, `features/cheques/presentation/cheques_page.dart` | Yes | **NO** | **NO** | Settlement, receipts, print |
| `financial_management/views/screens/expenses_screen.dart`, `taxes_screen.dart` | `features/expenses/presentation/expenses_page.dart` | Yes | **NO** | **NO** | Expense tax, allocation and filters |
| `views/screens/offers_screen.dart`, `offer_orders_screen.dart` | `features/offers/presentation/offers_page.dart` | Yes | **NO** | **NO** | Offer order conversion |
| `views/screens/repair_requests_screen.dart`, `repair_request_details_screen.dart`, `repair_receipt_screen.dart` | `features/repairs/presentation/repairs_page.dart` | Yes | **NO** | **NO** | Service state, parts, invoices, exports |
| `views/screens/reports_screen.dart`, `advanced_reports_screen.dart`, `sales_analytics_screen.dart`, `exports_screen.dart` | `features/reports/presentation/{reports,sales_analytics}_page.dart` | Yes | **NO** | **NO** | Report formatting parity still missing |
| `chat/views/screens/*.dart` | `features/chat/presentation/chat_page.dart` | Yes | **NO** | **NO** | Messages, groups, attachments, notifications |
| `views/screens/notes_screen.dart`, `activity_log_screen.dart`, `notifications_screen.dart`, `settings_screen.dart`, `user_management_screen.dart` | `features/{notes,activity_log,notifications,settings}/**` | Mixed | **NO** | **NO** | Expand all screen actions before closure |
| `salon_booking/**` | **Excluded by owner request** | N/A | N/A | N/A | Deliberately out of scope |

**Do not infer full parity from this grouped table.** Each group is a parent work item; expand into every V1 screen and interactive element with screenshots during implementation. Include dark mode, language/theme, statistics, profile/change-password, invoice/PDF/export dialogs and any supplementary V1 widgets omitted from this first grouped table.

## Audit evidence and gates

- Initial file inventory V1: 462 blobs, V2: 298 blobs, pinned in `2026-10-23-system-audit.md`.
- `docs/V2_FEATURE_PARITY_MATRIX.md` is a historical implementation checklist, not the source of acceptance truth.
- Start UI port with authentication after verifying secure store membership bootstrap. Do not copy V1 direct Firestore access or its shared-preferences password persistence.
- Required screenshot sizes: narrow phone, tablet and desktop; compare V1 and V2 from same locale/theme/state/data fixtures with strict design checklist. Screenshot automation is not yet run.
