import 'package:flutter/material.dart';

import '../../../core/errors/failure.dart';
import '../../../core/idempotency/idempotency_key.dart';
import '../../../core/money/money.dart';
import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../domain/entities/account.dart';
import '../domain/entities/journal_entry.dart';
import '../domain/entities/journal_line.dart';
import '../domain/repositories/accounting_query_repository.dart';
import '../domain/repositories/accounting_repository.dart';

class ManualJournalPage extends StatefulWidget {
  const ManualJournalPage({
    required this.repository,
    required this.queryRepository,
    required this.user,
    required this.membership,
    super.key,
  });

  final AccountingRepository? repository;
  final AccountingQueryRepository? queryRepository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<ManualJournalPage> createState() => _ManualJournalPageState();
}

class _ManualJournalPageState extends State<ManualJournalPage> {
  static const _currency = 'ILS';

  final _descriptionController = TextEditingController();
  final _lines = <_JournalLineDraft>[_JournalLineDraft(), _JournalLineDraft()];

  List<Account> _accounts = const <Account>[];
  DateTime _postedAt = DateTime.now();
  bool _isLoadingAccounts = true;
  bool _isPosting = false;
  String? _errorMessage;

  Money get _totalDebit => _sum((line) => line.debitController.text);

  Money get _totalCredit => _sum((line) => line.creditController.text);

  Money get _difference => (_totalDebit - _totalCredit).absolute;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.repository == null || widget.queryRepository == null) {
      return const Center(child: Text('مستودع القيود غير موصول بهذه البيئة.'));
    }
    if (_isLoadingAccounts) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return _buildErrorState();
    }
    if (_accounts.isEmpty) {
      return const Center(child: Text('لا توجد حسابات ترحيل متاحة.'));
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.menu_book_outlined, size: 30),
                        const SizedBox(width: 10),
                        Text(
                          'قيد يومية يدوي',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'يُرحّل القيد والسطور وتحديث أرصدة الحسابات معاً داخل عملية ذرية.',
                    ),
                    const SizedBox(height: 24),
                    _buildDateSelector(),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descriptionController,
                      enabled: !_isPosting,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'وصف القيد',
                        hintText: 'مثال: قيد تسوية أو مصروف غير مرتبط بمستند',
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                    ),
                    const SizedBox(height: 20),
                    for (final indexedLine in _lines.indexed)
                      _buildLine(indexedLine.$1, indexedLine.$2),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _isPosting ? null : _addLine,
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة سطر'),
                    ),
                    const SizedBox(height: 16),
                    _buildTotals(context),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _isPosting ? null : _postJournal,
                      icon: _isPosting
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: Text(
                        _isPosting ? 'جارٍ الترحيل...' : 'ترحيل القيد',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    return Row(
      children: [
        Expanded(
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'تاريخ القيد',
              prefixIcon: Icon(Icons.calendar_today_outlined),
            ),
            child: Text(_formatDate(_postedAt)),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: _isPosting ? null : _pickDate,
          icon: const Icon(Icons.edit_calendar_outlined),
          label: const Text('اختيار'),
        ),
      ],
    );
  }

  Widget _buildLine(int index, _JournalLineDraft line) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'السطر ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_lines.length > 2)
                  IconButton(
                    tooltip: 'حذف السطر',
                    onPressed: _isPosting ? null : () => _removeLine(index),
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: line.accountId,
              decoration: const InputDecoration(
                labelText: 'الحساب',
                prefixIcon: Icon(Icons.account_tree_outlined),
              ),
              items: _accounts
                  .map(
                    (account) => DropdownMenuItem<String>(
                      value: account.id,
                      child: Text(
                        '${account.code} — ${account.name}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _isPosting
                  ? null
                  : (value) {
                      setState(() => line.accountId = value);
                    },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: line.debitController,
                    enabled: !_isPosting,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'مدين',
                      hintText: '0.00',
                      prefixIcon: Icon(Icons.arrow_downward),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: line.creditController,
                    enabled: !_isPosting,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'دائن',
                      hintText: '0.00',
                      prefixIcon: Icon(Icons.arrow_upward),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: line.descriptionController,
              enabled: !_isPosting,
              decoration: const InputDecoration(
                labelText: 'وصف السطر (اختياري)',
                prefixIcon: Icon(Icons.short_text),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotals(BuildContext context) {
    final balanced = _difference.isZero && !_totalDebit.isZero;
    final statusColor = balanced ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text('إجمالي المدين'),
              const Spacer(),
              Text(
                _totalDebit.formatted,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('إجمالي الدائن'),
              const Spacer(),
              Text(
                _totalCredit.formatted,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            children: [
              Text(
                balanced ? 'القيد متوازن' : 'الفرق',
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                balanced ? 'جاهز للترحيل' : _difference.formatted,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _postedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'اختر تاريخ القيد',
      cancelText: 'إلغاء',
      confirmText: 'تأكيد',
    );
    if (!mounted || selected == null) {
      return;
    }
    setState(() {
      _postedAt = DateTime(selected.year, selected.month, selected.day);
    });
  }

  Future<void> _postJournal() async {
    final repository = widget.repository;
    if (repository == null) {
      _showMessage('مستودع القيود غير موصول بهذه البيئة.');
      return;
    }

    final accountsById = <String, Account>{
      for (final account in _accounts) account.id: account,
    };
    final journalLines = <JournalLine>[];

    for (var index = 0; index < _lines.length; index++) {
      final draft = _lines[index];
      final accountId = draft.accountId;
      if (accountId == null || accountId.isEmpty) {
        _showMessage('اختر حساباً للسطر ${index + 1}.');
        return;
      }

      final account = accountsById[accountId];
      if (account == null || !account.canPost) {
        _showMessage('الحساب المحدد للسطر ${index + 1} غير صالح للترحيل.');
        return;
      }
      if (account.currency != _currency) {
        _showMessage(
          'عملة الحساب ${account.code} مختلفة عن عملة القيد الحالية.',
        );
        return;
      }

      final debit = _parseMoney(draft.debitController.text);
      final credit = _parseMoney(draft.creditController.text);
      if (debit == null || credit == null) {
        _showMessage('تحقق من قيمة المدين والدائن في السطر ${index + 1}.');
        return;
      }

      final hasDebit = !debit.isZero;
      final hasCredit = !credit.isZero;
      if (hasDebit == hasCredit) {
        _showMessage('يجب إدخال قيمة في جهة واحدة فقط للسطر ${index + 1}.');
        return;
      }

      try {
        journalLines.add(
          JournalLine(
            id: 'manual-line-${index + 1}',
            accountId: accountId,
            debit: debit,
            credit: credit,
            description: draft.descriptionController.text.trim().isEmpty
                ? null
                : draft.descriptionController.text.trim(),
          ),
        );
      } on ArgumentError catch (error) {
        _showMessage(error.message?.toString() ?? 'سطر القيد غير صالح.');
        return;
      }
    }

    final totalDebit = journalLines.fold(
      Money.zero(currency: _currency),
      (sum, line) => sum + line.debit,
    );
    final totalCredit = journalLines.fold(
      Money.zero(currency: _currency),
      (sum, line) => sum + line.credit,
    );
    if (totalDebit.isZero || totalDebit != totalCredit) {
      _showMessage('القيد غير متوازن. يجب أن يتساوى المدين مع الدائن.');
      return;
    }

    final entryId = 'manual-journal-${DateTime.now().microsecondsSinceEpoch}';
    final description = _descriptionController.text.trim();
    late final JournalEntry entry;
    try {
      entry = JournalEntry(
        id: entryId,
        storeId: widget.membership.storeId,
        idempotencyKey: IdempotencyKey(entryId).value,
        postedAt: _postedAt.toUtc(),
        sourceType: 'manualJournal',
        description: description.isEmpty ? null : description,
        lines: journalLines,
      );
    } on ArgumentError catch (error) {
      _showMessage(error.message?.toString() ?? 'القيد غير صالح.');
      return;
    }

    setState(() => _isPosting = true);
    final result = await repository.postJournalEntry(
      context: StoreContext(
        storeId: widget.membership.storeId,
        userId: widget.user.id,
      ),
      entry: entry,
    );
    if (!mounted) {
      return;
    }
    setState(() => _isPosting = false);

    if (result is FailureResult<JournalEntry>) {
      final failure = result.failure;
      if (failure is QueuedFailure) {
        _showMessage('تم حفظ القيد للطابور وسيُرحّل عند عودة الاتصال.');
      } else {
        _showMessage(failure.message);
      }
      return;
    }

    if (result is Success<JournalEntry>) {
      for (final line in _lines) {
        line.dispose();
      }
      setState(() {
        _lines
          ..clear()
          ..addAll([_JournalLineDraft(), _JournalLineDraft()]);
        _descriptionController.clear();
        _postedAt = DateTime.now();
      });
      _showMessage('تم ترحيل القيد وتحديث الدفتر والأرصدة بنجاح.');
    }
  }

  Money _sum(String Function(_JournalLineDraft line) read) {
    var total = Money.zero(currency: _currency);
    for (final line in _lines) {
      final amount = _parseMoney(read(line));
      if (amount != null) {
        total += amount;
      }
    }
    return total;
  }

  Money? _parseMoney(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      return Money.zero(currency: _currency);
    }
    if (normalized.startsWith('-')) {
      return null;
    }

    final parts = normalized.split('.');
    if (parts.length > 2 ||
        parts.first.isEmpty ||
        int.tryParse(parts.first) == null ||
        (parts.length == 2 &&
            parts[1].isNotEmpty &&
            (parts[1].length > 2 || int.tryParse(parts[1]) == null))) {
      return null;
    }

    final major = int.parse(parts.first);
    final fraction = parts.length == 1 || parts[1].isEmpty
        ? 0
        : int.parse(parts[1].padRight(2, '0'));
    return Money(minorUnits: major * 100 + fraction, currency: _currency);
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '${date.year}/$month/$day';
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          Text(_errorMessage!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loadAccounts,
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadAccounts() async {
    final repository = widget.queryRepository;
    if (repository == null) {
      if (mounted) {
        setState(() => _isLoadingAccounts = false);
      }
      return;
    }

    setState(() {
      _isLoadingAccounts = true;
      _errorMessage = null;
    });
    final result = await repository.getAccounts(
      context: StoreContext(
        storeId: widget.membership.storeId,
        userId: widget.user.id,
      ),
    );
    if (!mounted) {
      return;
    }

    if (result is FailureResult<List<Account>>) {
      setState(() {
        _isLoadingAccounts = false;
        _errorMessage = result.failure.message;
      });
      return;
    }

    if (result is Success<List<Account>>) {
      final accounts = result.value.where((account) => account.canPost).toList()
        ..sort((left, right) => left.code.compareTo(right.code));
      setState(() {
        _isLoadingAccounts = false;
        _accounts = accounts;
      });
    }
  }

  void _addLine() {
    setState(() => _lines.add(_JournalLineDraft()));
  }

  void _removeLine(int index) {
    final removed = _lines.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    _descriptionController.dispose();
    super.dispose();
  }
}

class _JournalLineDraft {
  String? accountId;
  final debitController = TextEditingController();
  final creditController = TextEditingController();
  final descriptionController = TextEditingController();

  void dispose() {
    debitController.dispose();
    creditController.dispose();
    descriptionController.dispose();
  }
}
