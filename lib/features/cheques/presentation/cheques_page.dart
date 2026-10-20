import 'package:flutter/material.dart';

import '../../../core/errors/failure.dart';
import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../domain/entities/cheque.dart';
import '../domain/entities/cheque_settlement_result.dart';
import '../domain/enums/cheque_settlement_action.dart';
import '../domain/enums/cheque_status.dart';
import '../domain/repositories/cheque_repository.dart';

class ChequesPage extends StatefulWidget {
  const ChequesPage({
    required this.repository,
    required this.user,
    required this.membership,
    super.key,
  });

  final ChequeRepository? repository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<ChequesPage> createState() => _ChequesPageState();
}

class _ChequesPageState extends State<ChequesPage> {
  String _filter = 'all';
  List<Cheque> _cheques = const <Cheque>[];
  String? _errorMessage;
  String? _busyChequeId;
  bool _isLoading = true;

  StoreContext get _context {
    return StoreContext(
      storeId: widget.membership.storeId,
      userId: widget.user.id,
    );
  }

  ChequeStatus? get _statusFilter {
    switch (_filter) {
      case 'pending':
        return ChequeStatus.pending;
      case 'cleared':
        return ChequeStatus.cleared;
      case 'bounced':
        return ChequeStatus.bounced;
      default:
        return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.repository == null) {
      return const Center(
        child: Text('مستودع الشيكات غير موصول بهذه البيئة.'),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.payments_outlined, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'الشيكات الواردة',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<String>(
                    initialValue: _filter,
                    decoration: const InputDecoration(
                      labelText: 'الحالة',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('الكل')),
                      DropdownMenuItem(
                        value: 'pending',
                        child: Text('قيد التحصيل'),
                      ),
                      DropdownMenuItem(
                        value: 'cleared',
                        child: Text('تم التحصيل'),
                      ),
                      DropdownMenuItem(
                        value: 'bounced',
                        child: Text('مرتجع'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _filter = value);
                        _load();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'تحديث',
                  onPressed: _isLoading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }
    if (_cheques.isEmpty) {
      return const Center(child: Text('لا توجد شيكات ضمن الفلتر الحالي.'));
    }

    return ListView.separated(
      itemCount: _cheques.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _buildChequeCard(_cheques[index]),
    );
  }

  Widget _buildChequeCard(Cheque cheque) {
    final isBusy = _busyChequeId == cheque.id;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'شيك رقم ' + cheque.chequeNumber,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Chip(label: Text(_statusLabel(cheque.status))),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                Text('المبلغ: ' + cheque.amount.formatted),
                Text('البنك: ' + cheque.bankName),
                Text('العميل: ' + cheque.partyId),
                Text('تاريخ الاستلام: ' + _formatDate(cheque.receivedAt)),
                if (cheque.dueDate != null)
                  Text('الاستحقاق: ' + _formatDate(cheque.dueDate!)),
              ],
            ),
            if (cheque.description?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(cheque.description!),
            ],
            if (cheque.status == ChequeStatus.pending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isBusy
                          ? null
                          : () => _settle(
                                cheque,
                                ChequeSettlementAction.clear,
                              ),
                      icon: isBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.account_balance_outlined),
                      label: const Text('تحصيل في البنك'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isBusy
                          ? null
                          : () => _settle(
                                cheque,
                                ChequeSettlementAction.bounce,
                              ),
                      icon: const Icon(Icons.undo_outlined),
                      label: const Text('ارتجاع'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _settle(
    Cheque cheque,
    ChequeSettlementAction action,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(action == ChequeSettlementAction.clear
            ? 'تأكيد تحصيل الشيك'
            : 'تأكيد ارتجاع الشيك'),
        content: Text(
          action == ChequeSettlementAction.clear
              ? 'سيُنقل الشيك من قيد التحصيل إلى البنك.'
              : 'سيُعاد المبلغ على ذمة العميل ويُسجّل قيد الارتجاع.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || widget.repository == null) {
      return;
    }

    setState(() => _busyChequeId = cheque.id);
    final result = await widget.repository!.settleCheque(
      context: _context,
      chequeId: cheque.id,
      action: action,
      bankAccountId: action == ChequeSettlementAction.clear
          ? '1121'
          : null,
    );
    if (!mounted) {
      return;
    }
    setState(() => _busyChequeId = null);

    if (result is FailureResult<ChequeSettlementResult>) {
      final failure = result.failure;
      if (failure is QueuedFailure) {
        _showMessage('تم حفظ التسوية للطابور وستُرحّل عند عودة الاتصال.');
      } else {
        _showMessage(failure.message);
      }
      return;
    }
    if (result is Success<ChequeSettlementResult>) {
      _showMessage(
        action == ChequeSettlementAction.clear
            ? 'تم تحصيل الشيك ونقله إلى البنك.'
            : 'تم تسجيل ارتجاع الشيك وإعادته على ذمة العميل.',
      );
      await _load();
    }
  }

  Future<void> _load() async {
    final repository = widget.repository;
    if (repository == null) {
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final result = await repository.getCheques(
      context: _context,
      status: _statusFilter,
    );
    if (!mounted) {
      return;
    }
    if (result is FailureResult<List<Cheque>>) {
      setState(() {
        _isLoading = false;
        _errorMessage = result.failure.message;
      });
      return;
    }
    setState(() {
      _cheques = (result as Success<List<Cheque>>).value;
      _isLoading = false;
    });
  }

  String _statusLabel(ChequeStatus status) {
    switch (status) {
      case ChequeStatus.pending:
        return 'قيد التحصيل';
      case ChequeStatus.cleared:
        return 'تم التحصيل';
      case ChequeStatus.bounced:
        return 'مرتجع';
    }
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    return local.year.toString() +
        '/' +
        local.month.toString().padLeft(2, '0') +
        '/' +
        local.day.toString().padLeft(2, '0');
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
