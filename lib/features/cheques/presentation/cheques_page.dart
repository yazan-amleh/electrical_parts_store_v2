import 'package:flutter/material.dart';

import '../../../core/errors/failure.dart';
import '../../../core/idempotency/idempotency_key.dart';
import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../../parties/domain/enums/party_type.dart';
import '../domain/entities/cheque.dart';
import '../domain/entities/cheque_settlement_request.dart';
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
  int _loadEpoch = 0;
  final Map<String, _PendingChequeSettlement> _pendingSettlements =
      <String, _PendingChequeSettlement>{};

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
  void didUpdateWidget(covariant ChequesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.id != widget.user.id ||
        oldWidget.membership.storeId != widget.membership.storeId) {
      _cheques = const <Cheque>[];
      _pendingSettlements.clear();
      _filter = 'all';
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.repository == null) {
      return const Center(child: Text('مستودع الشيكات غير موصول بهذه البيئة.'));
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
                    value: _filter,
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
                      DropdownMenuItem(value: 'bounced', child: Text('مرتجع')),
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
    final pending = _pendingSettlements[cheque.id];
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
                    '${cheque.partyType == PartyType.customer ? 'شيك وارد' : 'شيك صادر'} رقم ${cheque.chequeNumber}',
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
                Text('المبلغ: ${cheque.amount.formatted}'),
                Text('البنك: ${cheque.bankName}'),
                Text(
                  '${cheque.partyType == PartyType.customer ? 'العميل' : 'المورد'}: ${cheque.partyId}',
                ),
                Text('تاريخ الاستلام: ${_formatDate(cheque.receivedAt)}'),
                if (cheque.dueDate != null)
                  Text('الاستحقاق: ${_formatDate(cheque.dueDate!)}'),
              ],
            ),
            if (cheque.description?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(cheque.description!),
            ],
            if (pending != null) ...[
              const SizedBox(height: 12),
              MaterialBanner(
                content: Text(
                  pending.queued
                      ? 'تسوية هذا الشيك محفوظة في طابور التنفيذ. '
                          'لا تنشئ تسوية أخرى حتى تتغير حالة الشيك.'
                      : 'تعذر التأكد من نتيجة التسوية السابقة. '
                          'أعد نفس الطلب حرفيًا لتأكيد النتيجة.',
                ),
                actions: [
                  if (!pending.queued)
                    TextButton.icon(
                      onPressed: isBusy
                          ? null
                          : () => _submitSettlement(cheque, pending),
                      icon: const Icon(Icons.refresh),
                      label: const Text('إعادة نفس التسوية'),
                    ),
                ],
              ),
            ],
            if (cheque.status == ChequeStatus.pending && pending == null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isBusy
                          ? null
                          : () => _settle(cheque, ChequeSettlementAction.clear),
                      icon: isBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.account_balance_outlined),
                      label: Text(
                        cheque.partyType == PartyType.customer
                            ? 'تحصيل في البنك'
                            : 'صرف عبر البنك',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isBusy
                          ? null
                          : () =>
                              _settle(cheque, ChequeSettlementAction.bounce),
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
    final existing = _pendingSettlements[cheque.id];
    if (existing != null) {
      if (existing.queued) {
        _showMessage(
          'تسوية هذا الشيك موجودة في طابور التنفيذ. '
          'انتظر تحديث حالته قبل إنشاء أمر آخر.',
        );
      } else {
        await _submitSettlement(cheque, existing);
      }
      return;
    }

    final isCustomer = cheque.partyType == PartyType.customer;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          action == ChequeSettlementAction.clear
              ? (isCustomer ? 'تأكيد تحصيل الشيك' : 'تأكيد صرف الشيك')
              : 'تأكيد ارتجاع الشيك',
        ),
        content: Text(
          action == ChequeSettlementAction.clear
              ? (isCustomer
                  ? 'سيُنقل الشيك من قيد التحصيل إلى البنك.'
                  : 'سيُنقل الشيك من الشيكات الصادرة إلى البنك.')
              : (isCustomer
                  ? 'سيُعاد المبلغ على ذمة العميل ويُسجّل قيد الارتجاع.'
                  : 'ستعود الذمة على المورد ويُسجّل قيد ارتجاع الشيك.'),
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

    final now = DateTime.now().toUtc();
    final key = 'cheque-${cheque.id}-${action.name}';
    final request = ChequeSettlementRequest(
      chequeId: cheque.id,
      action: action,
      idempotencyKey: IdempotencyKey(key),
      postedAt: now,
      bankAccountId: action == ChequeSettlementAction.clear ? '1121' : null,
    );
    final pending = _PendingChequeSettlement(request: request);
    _pendingSettlements[cheque.id] = pending;
    await _submitSettlement(cheque, pending);
  }

  Future<void> _submitSettlement(
    Cheque cheque,
    _PendingChequeSettlement pending,
  ) async {
    final repository = widget.repository;
    if (repository == null || _busyChequeId != null) {
      return;
    }
    final requestedStore = widget.membership.storeId;
    final requestedUser = widget.user.id;
    setState(() => _busyChequeId = cheque.id);

    final result = await repository.settleCheque(
      context: _context,
      request: pending.request,
    );
    if (!mounted ||
        requestedStore != widget.membership.storeId ||
        requestedUser != widget.user.id) {
      return;
    }
    setState(() => _busyChequeId = null);

    if (result is FailureResult<ChequeSettlementResult>) {
      final failure = result.failure;
      if (failure is QueuedFailure) {
        setState(() => pending.queued = true);
        _showMessage(
          'تم حفظ نفس تسوية الشيك للطابور. '
          'لن يسمح النظام بإنشاء تسوية أخرى لهذا الشيك حاليًا.',
        );
      } else if (failure is InfrastructureFailure) {
        _showMessage(
          'تعذر التأكد من نتيجة التسوية. استخدم «إعادة نفس التسوية» '
          'حتى يبقى التاريخ والمفتاح المحاسبيان كما هما.',
        );
      } else {
        _pendingSettlements.remove(cheque.id);
        _showMessage(failure.message);
      }
      return;
    }

    _pendingSettlements.remove(cheque.id);
    final posted = (result as Success<ChequeSettlementResult>).value;
    final isCustomer = cheque.partyType == PartyType.customer;
    _showMessage(
      posted.status == ChequeStatus.cleared
          ? (isCustomer
              ? 'تم تحصيل الشيك ونقله إلى البنك.'
              : 'تم صرف الشيك ونقله من الالتزام إلى البنك.')
          : (isCustomer
              ? 'تم تسجيل ارتجاع الشيك وإعادته على ذمة العميل.'
              : 'تم تسجيل ارتجاع الشيك وإعادته على ذمة المورد.'),
    );
    await _load();
  }

  Future<void> _load() async {
    final repository = widget.repository;
    if (repository == null) {
      return;
    }
    final epoch = ++_loadEpoch;
    final requestedStore = widget.membership.storeId;
    final requestedUser = widget.user.id;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final result = await repository.getCheques(
      context: _context,
      status: _statusFilter,
    );
    if (!mounted ||
        epoch != _loadEpoch ||
        requestedStore != widget.membership.storeId ||
        requestedUser != widget.user.id) {
      return;
    }
    if (result is FailureResult<List<Cheque>>) {
      setState(() {
        _isLoading = false;
        _errorMessage = result.failure.message;
      });
      return;
    }
    final cheques = (result as Success<List<Cheque>>).value;
    if (_statusFilter == null || _statusFilter == ChequeStatus.pending) {
      final visibleById = <String, Cheque>{
        for (final cheque in cheques) cheque.id: cheque,
      };
      _pendingSettlements.removeWhere((chequeId, _) {
        final cheque = visibleById[chequeId];
        return cheque == null || cheque.status != ChequeStatus.pending;
      });
    }
    setState(() {
      _cheques = cheques;
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
    return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
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

class _PendingChequeSettlement {
  _PendingChequeSettlement({required this.request});

  final ChequeSettlementRequest request;
  bool queued = false;
}
