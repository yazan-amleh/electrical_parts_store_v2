import 'package:flutter/material.dart';

import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../../auth/domain/enums/store_role.dart';
import '../../parties/domain/enums/party_type.dart';
import '../../parties/domain/repositories/party_repository.dart';
import '../domain/repositories/party_payment_repository.dart';
import '../domain/repositories/voucher_query_repository.dart';
import '../domain/repositories/voucher_draft_repository.dart';
import 'voucher_drafts_page.dart';
import 'voucher_register_page.dart';
import 'party_payments_page.dart';

/// Receipt/payment entry and paginated register for existing posted V2 payments.
/// Draft approval is separate from posted financial transactions.
class VouchersHubPage extends StatelessWidget {
  const VouchersHubPage({
    required this.paymentRepository,
    required this.voucherQueryRepository,
    this.draftRepository,
    this.partyRepository,
    required this.user,
    required this.membership,
    super.key,
  });

  final PartyPaymentRepository? paymentRepository;
  final VoucherQueryRepository? voucherQueryRepository;
  final VoucherDraftRepository? draftRepository;
  final PartyRepository? partyRepository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  Widget build(BuildContext context) {
    final canReceive = membership.role.canPostAccounting;
    final canPay = membership.role.canPostAccounting;
    final tabs = <_HubSection>[
      if (canReceive)
        _HubSection(
          label: 'قبض',
          icon: Icons.south_west_rounded,
          child: PartyPaymentsPage(
            key: ValueKey('receipt-${membership.storeId}'),
            repository: paymentRepository,
            draftRepository: draftRepository,
            partyRepository: partyRepository,
            user: user,
            membership: membership,
            initialPartyType: PartyType.customer,
          ),
        ),
      if (canPay)
        _HubSection(
          label: 'دفع',
          icon: Icons.north_east_rounded,
          child: PartyPaymentsPage(
            key: ValueKey('payment-${membership.storeId}'),
            repository: paymentRepository,
            draftRepository: draftRepository,
            user: user,
            membership: membership,
            initialPartyType: PartyType.supplier,
          ),
        ),
      if (canPay && draftRepository != null)
        _HubSection(
          label: 'المسودات',
          icon: Icons.pending_actions_outlined,
          child: VoucherDraftsPage(
            repository: draftRepository,
            user: user,
            membership: membership,
          ),
        ),
      if (canPay)
        _HubSection(
          label: 'حركات',
          icon: Icons.history_rounded,
          child: VoucherRegisterPage(
            repository: voucherQueryRepository,
            user: user,
            membership: membership,
          ),
        ),
    ];

    if (tabs.isEmpty) {
      return const Center(
        child: Text('لا تملك صلاحية الوصول إلى مركز السندات.'),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        key: ValueKey(
          'voucher-tabs-${membership.storeId}-${membership.role.name}',
        ),
        length: tabs.length,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'مركز السندات المالية',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: TabBar(
                  key: const ValueKey('vouchers-hub-tabs'),
                  tabs: [
                    for (final tab in tabs)
                      Tab(
                        icon: Icon(tab.icon, size: 18),
                        text: tab.label,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                children: [for (final tab in tabs) tab.child],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HubSection {
  const _HubSection({
    required this.label,
    required this.icon,
    required this.child,
  });

  final String label;
  final IconData icon;
  final Widget child;
}
