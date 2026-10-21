import 'package:flutter/material.dart';

import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../domain/entities/activity_log.dart';
import '../domain/repositories/activity_log_repository.dart';

class ActivityLogPage extends StatefulWidget {
  const ActivityLogPage({
    required this.repository,
    required this.user,
    required this.membership,
    super.key,
  });

  final ActivityLogRepository repository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<ActivityLogPage> createState() => _ActivityLogPageState();
}

class _ActivityLogPageState extends State<ActivityLogPage> {
  late final StoreContext _context;
  late final Stream<Result<List<ActivityLog>>> _logs;

  @override
  void initState() {
    super.initState();
    _context = StoreContext(
      storeId: widget.membership.storeId,
      userId: widget.user.id,
    );
    _logs = widget.repository.watchLogs(context: _context);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('سجل النشاط')),
        body: StreamBuilder<Result<List<ActivityLog>>>(
          stream: _logs,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text(snapshot.error.toString()));
            }
            final result = snapshot.data;
            if (result is FailureResult<List<ActivityLog>>) {
              return Center(child: Text(result.failure.message));
            }
            final logs = result is Success<List<ActivityLog>>
                ? result.value
                : const <ActivityLog>[];
            if (logs.isEmpty) {
              return const Center(child: Text('لا يوجد نشاط مسجل بعد.'));
            }
            return RefreshIndicator(
              onRefresh: () async {},
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: logs.length,
                separatorBuilder: (_, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final log = logs[index];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Icon(_iconFor(log.type)),
                      ),
                      title: Text(log.description),
                      subtitle: Text(
                        <String>[
                          log.type.arabicLabel,
                          if (log.userName?.trim().isNotEmpty == true)
                            log.userName!,
                          _formatDate(log.occurredAt),
                        ].join(' · '),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  IconData _iconFor(ActivityType type) {
    switch (type) {
      case ActivityType.saleCreated:
        return Icons.point_of_sale_outlined;
      case ActivityType.purchasePosted:
        return Icons.shopping_cart_outlined;
      case ActivityType.paymentPosted:
        return Icons.payments_outlined;
      case ActivityType.customerChanged:
        return Icons.people_outline;
      case ActivityType.supplierChanged:
        return Icons.local_shipping_outlined;
      case ActivityType.productChanged:
        return Icons.inventory_2_outlined;
      case ActivityType.categoryChanged:
        return Icons.category_outlined;
      case ActivityType.offerChanged:
        return Icons.request_quote_outlined;
      case ActivityType.expensePosted:
        return Icons.receipt_long_outlined;
      case ActivityType.repairChanged:
        return Icons.build_outlined;
      case ActivityType.accountingPosted:
        return Icons.account_balance_outlined;
      case ActivityType.system:
        return Icons.settings_outlined;
      case ActivityType.other:
        return Icons.info_outline;
    }
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$year/$month/$day $hour:$minute';
  }
}
