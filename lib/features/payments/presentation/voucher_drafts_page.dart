import 'package:flutter/material.dart';

import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../domain/entities/voucher_draft.dart';
import '../domain/repositories/voucher_draft_repository.dart';

class VoucherDraftsPage extends StatefulWidget {
  const VoucherDraftsPage({
    required this.repository,
    required this.user,
    required this.membership,
    super.key,
  });

  final VoucherDraftRepository? repository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<VoucherDraftsPage> createState() => _VoucherDraftsPageState();
}

class _VoucherDraftsPageState extends State<VoucherDraftsPage> {
  List<VoucherDraft> _drafts = const [];
  String? _error;
  bool _loading = false;
  String? _busyId;
  int _epoch = 0;

  StoreContext get _context => StoreContext(
        storeId: widget.membership.storeId,
        userId: widget.user.id,
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant VoucherDraftsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.membership.storeId != widget.membership.storeId ||
        oldWidget.user.id != widget.user.id) {
      _load();
    }
  }

  Future<void> _load() async {
    final repository = widget.repository;
    if (repository == null) return;
    final epoch = ++_epoch;
    final context = _context;
    setState(() {
      _loading = true;
      _error = null;
      _drafts = const [];
    });
    try {
      final result = await repository.getRecentDrafts(context: context);
      if (!mounted || epoch != _epoch) return;
      if (result is Success<List<VoucherDraft>>) {
        setState(() => _drafts = result.value);
      } else if (result is FailureResult<List<VoucherDraft>>) {
        setState(() => _error = result.failure.message);
      }
    } catch (error) {
      if (mounted && epoch == _epoch) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  Future<void> _act(
    VoucherDraft draft,
    Future<Result<void>> Function(VoucherDraftRepository, StoreContext) action,
  ) async {
    final repository = widget.repository;
    if (repository == null || _busyId != null) return;
    final context = _context;
    setState(() => _busyId = draft.id);
    try {
      final result = await action(repository, context);
      if (!mounted || _context.storeId != context.storeId ||
          _context.userId != context.userId) return;
      if (result is FailureResult<void>) {
        ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(content: Text(result.failure.message)),
        );
      } else {
        await _load();
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _reject(VoucherDraft draft) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('رفض السند'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'سبب الرفض (إلزامي)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('تأكيد الرفض'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || reason == null || reason.trim().isEmpty) return;
    await _act(
      draft,
      (repository, store) => repository.reject(
        context: store,
        draftId: draft.id,
        reason: reason.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.repository == null) {
      return const Center(child: Text('مستودع المسودات غير موصول بهذه البيئة.'));
    }
    final canApprove = widget.membership.role.canManageStore;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'المسودات لا تغير الأرصدة حتى اعتمادها وترحيلها.',
                  ),
                ),
                IconButton(
                  tooltip: 'تحديث المسودات',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'آخر 100 مسودة فقط. السند المرحّل لا يمكن تعديله من هنا.',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: _loading && _drafts.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _drafts.isEmpty
                    ? const Center(child: Text('لا توجد مسودات محفوظة.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _drafts.length,
                        itemBuilder: (context, index) {
                          final draft = _drafts[index];
                          final waiting = _busyId == draft.id;
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ListTile(
                                    title: Text(
                                      '${draft.partyType.name == 'customer' ? 'قبض' : 'دفع'} · ${draft.amount.formatted}',
                                    ),
                                    subtitle: Text(
                                      'المرجع: ${draft.id}\n'
                                      'الطرف: ${draft.partyId} · ${draft.statusLabel}'
                                      '${draft.journalEntryId == null ? '' : '\nالقيد: ${draft.journalEntryId}'}'
                                      '${draft.rejectionReason == null ? '' : '\nالرفض: ${draft.rejectionReason}'}',
                                    ),
                                    isThreeLine: true,
                                    trailing: waiting
                                        ? const CircularProgressIndicator()
                                        : null,
                                  ),
                                  if (draft.status == 'draft' &&
                                      draft.createdBy == widget.user.id)
                                    TextButton.icon(
                                      onPressed: _busyId != null
                                          ? null
                                          : () => _act(
                                                draft,
                                                (repository, store) =>
                                                    repository.submit(
                                                  context: store,
                                                  draftId: draft.id,
                                                ),
                                              ),
                                      icon: const Icon(Icons.send_outlined),
                                      label: const Text('إرسال للاعتماد'),
                                    ),
                                  if (draft.status == 'pendingApproval' &&
                                      canApprove)
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        FilledButton.icon(
                                          onPressed: _busyId != null
                                              ? null
                                              : () => _act(
                                                    draft,
                                                    (repository, store) =>
                                                        repository.approve(
                                                      context: store,
                                                      draftId: draft.id,
                                                    ),
                                                  ),
                                          icon: const Icon(
                                            Icons.check_circle_outline,
                                          ),
                                          label: const Text('اعتماد وترحيل'),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: _busyId != null
                                              ? null
                                              : () => _reject(draft),
                                          icon: const Icon(Icons.close),
                                          label: const Text('رفض'),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
