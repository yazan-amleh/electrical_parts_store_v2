import 'package:flutter/material.dart';

import '../../../core/quantity/quantity.dart';
import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../../auth/domain/enums/store_role.dart';
import '../../categories/domain/entities/category.dart';
import '../../categories/domain/repositories/category_repository.dart';
import '../domain/entities/inventory_count.dart';
import '../domain/repositories/inventory_count_repository.dart';

/// A stocktake is recorded separately from posted stock. Completion means
/// reviewed and awaiting approval; this screen never posts adjustments.
class InventoryCountPage extends StatefulWidget {
  const InventoryCountPage({
    required this.repository,
    required this.user,
    required this.membership,
    this.categoryRepository,
    super.key,
  });

  final InventoryCountRepository? repository;
  final CategoryRepository? categoryRepository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<InventoryCountPage> createState() => _InventoryCountPageState();
}

class _InventoryCountPageState extends State<InventoryCountPage> {
  List<InventoryCount> _counts = const [];
  List<Category> _categories = const [];
  InventoryCount? _selected;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  int _epoch = 0;
  String? _pendingCreateId;

  StoreContext get _scope => StoreContext(
        storeId: widget.membership.storeId,
        userId: widget.user.id,
      );

  bool get _canCount => widget.membership.role.canManageInventory;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant InventoryCountPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.id != widget.user.id ||
        oldWidget.membership.storeId != widget.membership.storeId ||
        oldWidget.repository != widget.repository ||
        oldWidget.categoryRepository != widget.categoryRepository) {
      ++_epoch;
      _counts = const [];
      _selected = null;
      _categories = const [];
      _pendingCreateId = null;
      _busy = false;
      _reload();
    }
  }

  bool _still(int epoch, StoreContext scope) =>
      mounted &&
      epoch == _epoch &&
      widget.membership.storeId == scope.storeId &&
      widget.user.id == scope.userId;

  Future<void> _reload() async {
    final repository = widget.repository;
    final categoriesRepo = widget.categoryRepository;
    final scope = _scope;
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _error = null;
    });
    if (repository == null) {
      setState(() => _loading = false);
      return;
    }
    final counts = await repository.listCounts(context: scope);
    if (!_still(epoch, scope) || widget.repository != repository) return;
    if (counts is FailureResult<List<InventoryCount>>) {
      setState(() {
        _loading = false;
        _error = counts.failure.message;
      });
      return;
    }
    List<Category> categories = const [];
    if (categoriesRepo != null) {
      final result = await categoriesRepo.getCategories(context: scope);
      if (!_still(epoch, scope) ||
          widget.categoryRepository != categoriesRepo) {
        return;
      }
      if (result is Success<List<Category>>) {
        categories = result.value
            .where((value) => value.storeId == scope.storeId)
            .toList(growable: false);
      }
    }
    if (counts is Success<List<InventoryCount>>) {
      if (counts.value.any((value) => value.storeId != scope.storeId)) {
        setState(() {
          _loading = false;
          _error = 'تم رفض جرد لا يخص المتجر الحالي.';
        });
        return;
      }
      setState(() {
        _counts = counts.value;
        _categories = categories;
        _loading = false;
      });
    }
  }

  Future<void> _openCount(String countId) async {
    final repository = widget.repository;
    if (repository == null) return;
    final scope = _scope;
    final epoch = _epoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await repository.getCount(context: scope, countId: countId);
    if (!_still(epoch, scope)) return;
    setState(() {
      _busy = false;
      if (result is Success<InventoryCount> &&
          result.value.storeId == scope.storeId) {
        _selected = result.value;
      } else if (result is FailureResult<InventoryCount>) {
        _error = result.failure.message;
      } else {
        _error = 'تعذر التحقق من الجرد الحالي.';
      }
    });
  }

  Future<void> _create() async {
    if (!_canCount || _busy || widget.repository == null) return;
    final notes = TextEditingController();
    String? categoryId;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('جرد جديد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'ستُحفظ نسخة من الكميات المسجلة في بداية العد. '
                'لا تُعدّل هذه الخطوة المخزون.',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                value: categoryId,
                decoration: const InputDecoration(labelText: 'نطاق الجرد'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('جميع الأصناف (حتى 150)'),
                  ),
                  for (final category in _categories)
                    DropdownMenuItem<String?>(
                      value: category.id,
                      child: Text(category.name),
                    ),
                ],
                onChanged: (value) => update(() => categoryId = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notes,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'ملاحظات الجرد'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('إنشاء مسودة'),
            ),
          ],
        ),
      ),
    );
    final description = notes.text.trim();
    notes.dispose();
    if (accepted != true || !mounted || !_canCount) return;

    final scope = _scope;
    final epoch = _epoch;
    final repository = widget.repository!;
    // Reuse the ID after an uncertain network outcome to avoid duplicate
    // drafts on a retry of the same logical creation request.
    final countId = _pendingCreateId ??=
        'count-${DateTime.now().toUtc().microsecondsSinceEpoch}';
    setState(() => _busy = true);
    final result = await repository.createCount(
      context: scope,
      countId: countId,
      categoryId: categoryId,
      notes: description,
    );
    if (!_still(epoch, scope)) return;
    setState(() => _busy = false);
    if (result is Success<InventoryCount>) {
      _pendingCreateId = null;
      await _reload();
      if (_still(_epoch, scope)) await _openCount(result.value.id);
    } else if (result is FailureResult<InventoryCount>) {
      // A certain validation/auth failure permits a genuinely new count.
      _pendingCreateId = null;
      _show(result.failure.message);
    }
  }

  Future<void> _editItem(InventoryCountItem item) async {
    final selected = _selected;
    final repository = widget.repository;
    if (selected == null ||
        selected.status != InventoryCountStatus.draft ||
        repository == null ||
        _busy ||
        !_canCount) {
      return;
    }

    final actual = TextEditingController(
      text: item.actualQuantity?.formatted ?? '',
    );
    final reason = TextEditingController(text: item.reason);
    final notes = TextEditingController(text: item.notes);
    bool reviewed = item.reviewed;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) => AlertDialog(
          title: Text(item.productName),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    'كمية النظام عند بدء الجرد: ${item.systemQuantity.formatted}'),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('count-actual-quantity'),
                  controller: actual,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'الكمية الفعلية'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: reason,
                  maxLength: 160,
                  decoration: const InputDecoration(
                    labelText: 'سبب الفرق (إلزامي عند وجود فرق)',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notes,
                  maxLength: 300,
                  decoration: const InputDecoration(labelText: 'ملاحظات'),
                ),
                CheckboxListTile(
                  value: reviewed,
                  title: const Text('تمت مراجعة الكمية'),
                  onChanged: (value) => update(() => reviewed = value ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حفظ العد'),
            ),
          ],
        ),
      ),
    );
    final raw = actual.text.trim().replaceAll(',', '.');
    final reasonText = reason.text.trim();
    final notesText = notes.text.trim();
    actual.dispose();
    reason.dispose();
    notes.dispose();
    if (accepted != true || !mounted) return;

    if (!RegExp(r'^\d+(?:\.\d{1,3})?$').hasMatch(raw)) {
      _show('الكمية يجب أن تكون عددًا غير سالب بدقة حتى 3 منازل.');
      return;
    }
    final quantity = Quantity.fromString(raw);
    if (quantity.milliUnits > 1000000000000 ||
        (reviewed && quantity != item.systemQuantity && reasonText.isEmpty)) {
      _show('تحقق من الكمية واكتب سببًا للفرق قبل المراجعة.');
      return;
    }
    final scope = _scope;
    final epoch = _epoch;
    setState(() => _busy = true);
    final result = await repository.saveItem(
      context: scope,
      countId: selected.id,
      expectedRevision: selected.revision,
      productId: item.productId,
      actualQuantity: quantity,
      reviewed: reviewed,
      reason: reasonText,
      notes: notesText,
    );
    if (!_still(epoch, scope)) return;
    setState(() => _busy = false);
    if (result is Success<InventoryCount>) {
      setState(() => _selected = result.value);
    } else if (result is FailureResult<InventoryCount>) {
      _show(result.failure.message);
      await _openCount(selected.id);
    }
  }

  Future<void> _complete() async {
    final count = _selected;
    final repository = widget.repository;
    if (count == null ||
        repository == null ||
        _busy ||
        !_canCount ||
        !count.canComplete) {
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إكمال الجرد'),
        content: const Text(
          'سيُغلق إدخال الكميات ويصبح الجرد بانتظار الاعتماد. '
          'لن تتغير أرصدة المخزون أو القيود المحاسبية.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إكمال'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    final scope = _scope;
    final epoch = _epoch;
    setState(() => _busy = true);
    final result = await repository.completeCount(
      context: scope,
      countId: count.id,
      expectedRevision: count.revision,
    );
    if (!_still(epoch, scope)) return;
    setState(() => _busy = false);
    if (result is Success<InventoryCount>) {
      setState(() => _selected = result.value);
    } else if (result is FailureResult<InventoryCount>) {
      _show(result.failure.message);
      await _openCount(count.id);
    }
  }

  Future<void> _cancel() async {
    final count = _selected;
    final repository = widget.repository;
    if (count == null ||
        repository == null ||
        _busy ||
        !_canCount ||
        (count.status != InventoryCountStatus.draft &&
            count.status != InventoryCountStatus.completed)) {
      return;
    }
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إلغاء الجرد'),
        content: TextField(
          controller: reason,
          decoration: const InputDecoration(labelText: 'سبب الإلغاء'),
          maxLength: 300,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد الإلغاء'),
          ),
        ],
      ),
    );
    final value = reason.text.trim();
    reason.dispose();
    if (accepted != true || !mounted) return;
    if (value.isEmpty) {
      _show('سبب الإلغاء مطلوب.');
      return;
    }
    final scope = _scope;
    final epoch = _epoch;
    setState(() => _busy = true);
    final result = await repository.cancelCount(
      context: scope,
      countId: count.id,
      expectedRevision: count.revision,
      reason: value,
    );
    if (!_still(epoch, scope)) return;
    setState(() => _busy = false);
    if (result is Success<InventoryCount>) {
      setState(() => _selected = result.value);
    } else if (result is FailureResult<InventoryCount>) {
      _show(result.failure.message);
      await _openCount(count.id);
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _status(InventoryCountStatus status) {
    switch (status) {
      case InventoryCountStatus.draft:
        return 'مسودة';
      case InventoryCountStatus.completed:
        return 'مكتمل — بانتظار الاعتماد';
      case InventoryCountStatus.approved:
        return 'معتمد';
      case InventoryCountStatus.rejected:
        return 'مرفوض';
      case InventoryCountStatus.cancelled:
        return 'ملغي';
    }
  }

  Widget _details(InventoryCount count) {
    final estimate = count.estimatedDifferenceByCurrency.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('الجرد ${count.id}',
            style: Theme.of(context).textTheme.titleMedium),
        Text('الحالة: ${_status(count.status)} • المراجعة ${count.revision}'),
        Text('تمت مراجعة ${count.reviewedItems} من ${count.items.length} صنف'),
        const Text(
          'فروقات تقديرية من أسعار الأصناف وقت إنشاء الجرد؛ '
          'لا تمثل قيودًا محاسبية أو قيمة معتمدة.',
        ),
        for (final value in estimate)
          Text('فرق التكلفة التقديري ${value.value.formatted}'),
        const SizedBox(height: 8),
        if (count.status == InventoryCountStatus.completed)
          const Card(
            child: ListTile(
              leading: Icon(Icons.pending_actions),
              title: Text('بانتظار اعتماد وتسوية محاسبية'),
              subtitle: Text(
                'لا يوجد ترحيل آلي للفروقات. '
                'الاعتماد يتطلب التحقق من الكميات والتكلفة الحالية '
                'ومنع تكرار القيود في معاملة ذرية.',
              ),
            ),
          ),
        if (_canCount && count.status == InventoryCountStatus.draft)
          FilledButton.icon(
            key: const ValueKey('stocktake-complete'),
            onPressed: _busy || !count.canComplete ? null : _complete,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('إكمال الجرد بعد مراجعة كل الأصناف'),
          ),
        if (_canCount &&
            (count.status == InventoryCountStatus.draft ||
                count.status == InventoryCountStatus.completed))
          TextButton.icon(
            onPressed: _busy ? null : _cancel,
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('إلغاء الجرد مع سبب'),
          ),
        const Divider(),
        for (final item in count.items)
          Card(
            child: ListTile(
              title: Text(item.productName),
              subtitle: Text(
                'النظام: ${item.systemQuantity.formatted} | '
                'الفعلي: ${item.actualQuantity?.formatted ?? 'لم يُعدّ'} | '
                'الفرق: ${item.difference?.formatted ?? '—'}'
                '${item.reviewed ? ' | تمت المراجعة' : ''}'
                '${item.reason.isNotEmpty ? ' | ${item.reason}' : ''}',
              ),
              leading: Icon(
                item.reviewed ? Icons.verified_outlined : Icons.hourglass_empty,
              ),
              trailing: _canCount && count.status == InventoryCountStatus.draft
                  ? IconButton(
                      tooltip: 'إدخال كمية ${item.productName}',
                      onPressed: _busy ? null : () => _editItem(item),
                      icon: const Icon(Icons.edit_note),
                    )
                  : null,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: widget.repository == null
          ? const Center(child: Text('خدمة الجرد غير متصلة بهذه البيئة.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'جرد المخزون',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'تحديث الجردات',
                      onPressed: _busy || _loading ? null : _reload,
                      icon: const Icon(Icons.refresh),
                    ),
                    if (_canCount)
                      FilledButton.icon(
                        key: const ValueKey('stocktake-create'),
                        onPressed: _busy || _loading ? null : _create,
                        icon: const Icon(Icons.add),
                        label: const Text('جرد جديد'),
                      ),
                  ],
                ),
                const Text(
                  'الجرد لا يغير مخزون المتجر. كل تسوية تحتاج '
                  'اعتمادًا وترحيلًا مستقلًا وآمنًا.',
                ),
                if (_loading) const Center(child: CircularProgressIndicator()),
                if (_error != null)
                  ListTile(
                    title: Text(_error!),
                    trailing: TextButton(
                      onPressed: _reload,
                      child: const Text('إعادة المحاولة'),
                    ),
                  ),
                if (!_loading) ...[
                  if (_counts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 22),
                      child: Text('لا توجد جردات محفوظة ضمن القائمة المحمّلة.'),
                    ),
                  for (final count in _counts)
                    Card(
                      child: ListTile(
                        title: Text('جرد ${count.id}'),
                        subtitle: Text(
                          '${_status(count.status)} • '
                          '${count.reviewedItems}/${count.items.length}',
                        ),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: _busy ? null : () => _openCount(count.id),
                      ),
                    ),
                ],
                if (_busy) const Center(child: LinearProgressIndicator()),
                if (_selected != null) ...[
                  const SizedBox(height: 16),
                  _details(_selected!),
                ],
              ],
            ),
    );
  }

  @override
  void dispose() {
    ++_epoch;
    super.dispose();
  }
}
