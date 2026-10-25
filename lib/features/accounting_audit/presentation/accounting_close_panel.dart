import 'package:flutter/material.dart';

import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/enums/store_role.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../data/repositories/firestore_accounting_close_repository.dart';

/// Explicit human-operated workflow: no implicit lock or automatic reopening.
class AccountingClosePanel extends StatefulWidget {
  const AccountingClosePanel({
    required this.repository,
    required this.membership,
    required this.userId,
    super.key,
  });

  final FirestoreAccountingCloseRepository repository;
  final StoreMembership membership;
  final String userId;

  @override
  State<AccountingClosePanel> createState() => _AccountingClosePanelState();
}

class _AccountingClosePanelState extends State<AccountingClosePanel> {
  Map<String, dynamic>? _state;
  Map<String, dynamic>? _progress;
  String? _error;
  bool _busy = false;

  StoreContext get _context => StoreContext(
        storeId: widget.membership.storeId,
        userId: widget.userId,
      );

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<Map<String, dynamic>?> _execute(
    Future<Result<Map<String, dynamic>>> Function() action,
  ) async {
    if (_busy) return null;
    setState(() {
      _busy = true;
      _error = null;
    });
    return _executeWithoutSpinner(action);
  }

  Future<Map<String, dynamic>?> _executeWithoutSpinner(
    Future<Result<Map<String, dynamic>>> Function() action,
  ) async {
    try {
      final result = await action();
      if (!mounted) return null;
      if (result is Success<Map<String, dynamic>>) {
        return result.value;
      }
      if (result is FailureResult<Map<String, dynamic>>) {
        setState(() => _error = result.failure.message);
      }
      return null;
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    final state = await _execute(
      () => widget.repository.status(_context),
    );
    if (!mounted || state == null) return;
    setState(() => _state = state);
  }

  Future<void> _begin() async {
    final today = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: DateTime(2010),
      lastDate: today,
      helpText: 'تاريخ نهاية الفترة المراد إقفالها',
    );
    if (!mounted || selected == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد إيقاف الحركات المالية'),
        content: const Text(
          'سيتوقف ترحيل جميع الحركات المالية المحمية فور بدء الإقفال. '
          'بعد التحقق من الفحوص يمكن تثبيته أو إعادة فتحه مع تسجيل السبب.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('بدء القفل'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    final date = DateTime.utc(selected.year, selected.month, selected.day)
        .toIso8601String()
        .substring(0, 10);
    final state = await _execute(
      () => widget.repository.begin(_context, date),
    );
    if (state != null) await _refresh();
  }

  Future<void> _startChecks() async {
    final state = await _execute(
      () => widget.repository.startScans(_context),
    );
    if (!mounted || state == null) return;
    setState(() {
      _state = state;
      _progress = null;
    });
  }

  Future<void> _advanceChecks() async {
    if (_busy) return;
    // Eight bounded server pages per click; state is saved server-side after
    // every page. The user can stop and resume after refreshing the browser.
    for (var i = 0; i < 8; i++) {
      final data = await _execute(
        () => widget.repository.advanceScans(_context),
      );
      if (!mounted || data == null) return;
      setState(() => _progress = data);
      if (data['complete'] == true || data['hasFailures'] == true) return;
    }
  }

  Future<void> _finalize() async {
    final runs = _state?['auditRuns'];
    if (runs is! Map || _progress?['complete'] != true) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تثبيت الإقفال المحاسبي'),
        content: const Text(
          'سيبقى الترحيل المالي مقفلاً بعد التثبيت. '
          'النتائج أدلة تدقيق وليست شهادة أرصدة تاريخية.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تثبيت الإقفال'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    final result = await _execute(
      () => widget.repository.finalize(
        _context,
        Map<String, dynamic>.from(runs),
      ),
    );
    if (result != null) await _refresh();
  }

  Future<void> _reopen() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إعادة فتح الحركات المالية'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'الفترات المقفلة سابقاً ستبقى محمية من القيود '
              'ذات التاريخ القديم. اذكر سبب فتح النظام.',
            ),
            TextField(
              controller: controller,
              maxLength: 400,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'سبب إعادة الفتح'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('فتح مع تسجيل السبب'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || reason == null || reason.trim().length < 12) return;
    final result = await _execute(
      () => widget.repository.reopen(_context, reason.trim()),
    );
    if (result != null) {
      setState(() => _progress = null);
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.membership.isActive ||
        !widget.membership.role.canManageStore) {
      return const SizedBox.shrink();
    }
    final status = _state?['status'] as String? ?? 'not_started';
    final started = _state?['auditRuns'] is Map;
    final scans = _progress?['scans'];
    final scanRows = scans is List ? scans : const <Object?>[];

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'إقفال الفترة المحاسبية — إدارة المالك',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'الحالة: $status | تاريخ الإقفال: '
              '${_state?['throughDate'] ?? '—'} | '
              'مقفل حتى: ${_state?['closedThroughDate'] ?? '—'}',
            ),
            const Text(
              'العملية توقف الكتابة المحاسبية المحمية، لكنها لا تصدر '
              'شهادة مالية ولا تغطي كتابات Firebase Admin الخارجية.',
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (scanRows.isNotEmpty)
              Text(
                scanRows.map((row) {
                  final item = Map<String, dynamic>.from(row as Map);
                  return '${item['name']}: ${item['status']}';
                }).join(' | '),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : _refresh,
                  child: const Text('تحديث الحالة'),
                ),
                if (status == 'not_started' || status == 'open')
                  FilledButton(
                    onPressed: _busy ? null : _begin,
                    child: const Text('بدء الإقفال'),
                  ),
                if (status == 'locked' && !started)
                  FilledButton(
                    onPressed: _busy ? null : _startChecks,
                    child: const Text('بدء الفحوص الأربعة'),
                  ),
                if (status == 'locked' && started)
                  FilledButton(
                    onPressed: _busy ? null : _advanceChecks,
                    child: const Text('استكمال الفحوص'),
                  ),
                if (status == 'locked' && _progress?['complete'] == true)
                  FilledButton(
                    onPressed: _busy ? null : _finalize,
                    child: const Text('تثبيت الإقفال'),
                  ),
                if (status == 'locked' || status == 'closed')
                  OutlinedButton(
                    onPressed: _busy ? null : _reopen,
                    child: const Text('إعادة الفتح مع سبب'),
                  ),
                if (_busy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
