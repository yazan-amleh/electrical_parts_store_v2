import 'package:flutter/material.dart';

import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../activity_log/domain/entities/activity_log.dart';
import '../../activity_log/domain/repositories/activity_log_repository.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../../auth/domain/enums/store_role.dart';
import '../../parties/domain/enums/party_type.dart';
import '../domain/repositories/party_payment_repository.dart';
import 'party_payments_page.dart';

/// V1-inspired entry point for receipts, payments and recent activity.
///
/// Only the posted payment workflow is currently backed by V2 domain services.
/// Historical payment events are a bounded activity feed, NOT an authoritative
/// voucher register or an equivalent of V1 draft/posted voucher documents.
class VouchersHubPage extends StatelessWidget {
  const VouchersHubPage({
    required this.paymentRepository,
    required this.activityLogRepository,
    required this.user,
    required this.membership,
    super.key,
  });

  final PartyPaymentRepository? paymentRepository;
  final ActivityLogRepository? activityLogRepository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  Widget build(BuildContext context) {
    final canReceive =
        membership.role.canManageSales || membership.role.canPostAccounting;
    final canPay = membership.role.canPostAccounting;
    final tabs = <_HubSection>[
      if (canReceive)
        _HubSection(
          label: 'قبض',
          icon: Icons.south_west_rounded,
          child: PartyPaymentsPage(
            key: ValueKey('receipt-${membership.storeId}'),
            repository: paymentRepository,
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
            user: user,
            membership: membership,
            initialPartyType: PartyType.supplier,
          ),
        ),
      _HubSection(
        label: 'حركات',
        icon: Icons.history_rounded,
        child: _RecentPaymentActivity(
          repository: activityLogRepository,
          user: user,
          membership: membership,
        ),
      ),
    ];

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

class _RecentPaymentActivity extends StatelessWidget {
  const _RecentPaymentActivity({
    required this.repository,
    required this.user,
    required this.membership,
  });

  final ActivityLogRepository? repository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  Widget build(BuildContext context) {
    final source = repository;
    if (source == null) {
      return const Center(
        child: Text('سجل حركات الدفع غير موصول بهذه البيئة.'),
      );
    }
    return StreamBuilder<Result<List<ActivityLog>>>(
      stream: source.watchLogs(
        context: StoreContext(
          storeId: membership.storeId,
          userId: user.id,
        ),
        limit: 100,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('تعذر قراءة سجل النشاط.'));
        }
        final result = snapshot.data;
        if (result is FailureResult<List<ActivityLog>>) {
          return Center(child: Text(result.failure.message));
        }
        final entries = result is Success<List<ActivityLog>>
            ? result.value
                .where((entry) => entry.type == ActivityType.paymentPosted)
                .toList()
            : <ActivityLog>[];

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('آخر أحداث القبض والدفع المسجلة'),
                subtitle: Text(
                  'يعرض هذا التبويب أحداث الدفع من آخر 100 سجل نشاط فقط. '
                  'ولا يمثل كشفًا شاملًا للسندات أو أرصدة مالية معتمدة.',
                ),
              ),
            ),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('لا توجد حركات قبض أو دفع في السجل المتاح.')),
              )
            else
              for (final entry in entries)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.payments_outlined),
                    title: Text(entry.description),
                    subtitle: Text(
                      '${entry.occurredAt.toLocal().toString().split('.').first}'
                      '${entry.userName == null ? '' : ' · ${entry.userName}'}',
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}
