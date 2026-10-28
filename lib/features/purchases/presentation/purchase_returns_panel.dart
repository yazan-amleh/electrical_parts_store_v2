import 'package:flutter/material.dart';

import '../../../core/errors/failure.dart';
import '../../../core/idempotency/idempotency_key.dart';
import '../../../core/money/money.dart';
import '../../../core/quantity/quantity.dart';
import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../../auth/domain/enums/store_role.dart';
import '../domain/entities/purchase_invoice.dart';
import '../domain/entities/purchase_return.dart';
import '../domain/repositories/purchase_repository.dart';

class PurchaseReturnsPanel extends StatefulWidget {
  const PurchaseReturnsPanel({
    required this.repository,
    required this.user,
    required this.membership,
    super.key,
  });

  final PurchaseRepository? repository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<PurchaseReturnsPanel> createState() => _PurchaseReturnsPanelState();
}

class _PurchaseReturnsPanelState extends State<PurchaseReturnsPanel> {
  static const _cashAccountId = '1110';
  static const _bankAccountId = '1121';
  static const _cardAccountId = '1160';
  static const _inventoryAccountId = '1150';
  static const _supplierPayableAccountId = '2110';
  static const _inputTaxAccountId = '1170';
  static const _purchaseReturnVarianceAccountId = '5200';

  List<PurchaseInvoiceSummary>? _invoices;
  PurchaseInvoiceDocument? _document;
  String? _selectedInvoiceId;
  String? _listError;
  String? _documentError;
  String? _postingInvoiceId;
  int _loadEpoch = 0;
  final Map<String, PurchaseReturn> _pendingReturns =
      <String, PurchaseReturn>{};

  StoreContext get _context => StoreContext(
        storeId: widget.membership.storeId,
        userId: widget.user.id,
      );

  bool get _canPostReturn {
    final role = widget.membership.role;
    return role.canPostAccounting || role.canManageSales;
  }

  @override
  void initState() {
    super.initState();
    _loadInvoices();
  }

  @override
  void didUpdateWidget(covariant PurchaseReturnsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.id != widget.user.id ||
        oldWidget.membership.storeId != widget.membership.storeId) {
      _invoices = null;
      _document = null;
      _selectedInvoiceId = null;
      _pendingReturns.clear();
      _loadInvoices();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.repository == null) {
      return const Center(
        child: Text('مستودع مردودات المشتريات غير موصول بهذه البيئة.'),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final list = _buildInvoiceList();
        final detail = _buildInvoiceDetail();
        if (constraints.maxWidth < 900) {
          return Column(
            children: [
              SizedBox(height: 300, child: list),
              Expanded(child: detail),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 390, child: list),
            Expanded(child: detail),
          ],
        );
      },
    );
  }

  Widget _buildInvoiceList() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
            child: Row(
              children: [
                const Icon(Icons.receipt_long_outlined),
                const SizedBox(width: 8),
                Text(
                  'فواتير الشراء',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'تحديث الفواتير',
                  onPressed: _loadInvoices,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('اختر فاتورة شراء مرحّلة لبدء المردود.'),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildInvoiceListBody()),
        ],
      ),
    );
  }

  Widget _buildInvoiceListBody() {
    final invoices = _invoices;
    if (invoices == null && _listError == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_listError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 38),
              const SizedBox(height: 8),
              Text(_listError!, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _loadInvoices,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }
    if (invoices == null || invoices.isEmpty) {
      return const Center(child: Text('لا توجد فواتير شراء مرحّلة.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: invoices.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final invoice = invoices[index];
        final selected = invoice.id == _selectedInvoiceId;
        return Card(
          color:
              selected ? Theme.of(context).colorScheme.primaryContainer : null,
          child: ListTile(
            selected: selected,
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    invoice.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                _statusChip(invoice),
              ],
            ),
            subtitle: Text(
              '${_dateLabel(invoice.postedAt)} • '
              '${_paymentLabel(invoice.paymentMethod)} • '
              '${invoice.total.formatted}',
            ),
            onTap: () => _selectInvoice(invoice.id),
          ),
        );
      },
    );
  }

  Widget _buildInvoiceDetail() {
    if (_selectedInvoiceId == null) {
      return const Card(
        margin: EdgeInsets.fromLTRB(0, 12, 12, 12),
        child: Center(
          child: Text('اختر فاتورة لعرض الأصناف والكميات المتبقية.'),
        ),
      );
    }
    if (_document == null && _documentError == null) {
      return const Card(
        margin: EdgeInsets.fromLTRB(0, 12, 12, 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_documentError != null) {
      return Card(
        margin: const EdgeInsets.fromLTRB(0, 12, 12, 12),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 38),
                const SizedBox(height: 8),
                Text(_documentError!, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => _selectInvoice(_selectedInvoiceId!),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة تحميل الفاتورة'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final document = _document!;
    final invoice = document.invoice;
    final returnableLines = document.lines
        .where((line) => line.remainingQuantityMilliUnits > 0)
        .toList(growable: false);
    final pending = _pendingReturns[invoice.id];
    final busy = _postingInvoiceId == invoice.id;

    return Card(
      margin: const EdgeInsets.fromLTRB(0, 12, 12, 12),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.assignment_return_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'مردود الفاتورة ${invoice.id}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    _statusChip(invoice),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    Text('التاريخ: ${_dateLabel(invoice.postedAt)}'),
                    Text(
                      'طريقة الدفع: ${_paymentLabel(invoice.paymentMethod)}',
                    ),
                    Text('قبل الضريبة: ${invoice.subtotal.formatted}'),
                    Text('الضريبة: ${invoice.tax.formatted}'),
                    Text('الإجمالي: ${invoice.total.formatted}'),
                  ],
                ),
                if (pending != null) ...[
                  const SizedBox(height: 10),
                  MaterialBanner(
                    content: const Text(
                      'يوجد مردود سابق لم نحصل على نتيجة مؤكدة له. '
                      'أعد المحاولة بنفس الطلب قبل إنشاء مردود جديد.',
                    ),
                    actions: [
                      TextButton(
                        onPressed:
                            busy ? null : () => _submitReturn(invoice, pending),
                        child: const Text('إعادة نفس الطلب'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: document.lines.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final line = document.lines[index];
                return ListTile(
                  leading: Icon(
                    line.isFullyReturned
                        ? Icons.undo
                        : Icons.inventory_2_outlined,
                  ),
                  title: Text(line.description),
                  subtitle: Text(
                    'المشترى: '
                    '${Quantity.fromMilliUnits(line.quantityMilliUnits).formatted} • '
                    'المرتجع: '
                    '${Quantity.fromMilliUnits(line.returnedQuantityMilliUnits).formatted} • '
                    'المتبقي: '
                    '${Quantity.fromMilliUnits(line.remainingQuantityMilliUnits).formatted} '
                    "${line.unitName ?? ''}",
                  ),
                  trailing: Text(line.total.formatted),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: !_canPostReturn ||
                            busy ||
                            pending != null ||
                            invoice.isFullyReturned ||
                            returnableLines.isEmpty
                        ? null
                        : () => _startPartialReturn(document),
                    icon: const Icon(Icons.playlist_add_check_circle_outlined),
                    label: const Text('مردود جزئي'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: !_canPostReturn ||
                            busy ||
                            pending != null ||
                            invoice.isFullyReturned ||
                            returnableLines.isEmpty
                        ? null
                        : () => _startRemainingReturn(document),
                    icon: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.undo),
                    label: Text(
                      invoice.isPartiallyReturned
                          ? 'إرجاع كل المتبقي'
                          : 'إرجاع الفاتورة بالكامل',
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!_canPostReturn)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'دور المستخدم الحالي لا يسمح بترحيل مردود مشتريات.',
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusChip(PurchaseInvoiceSummary invoice) {
    final text = invoice.isFullyReturned
        ? 'مُرجعة بالكامل'
        : invoice.isPartiallyReturned
            ? 'مُرجعة جزئيًا'
            : 'مرحّلة';
    final icon = invoice.isFullyReturned
        ? Icons.undo
        : invoice.isPartiallyReturned
            ? Icons.history
            : Icons.check_circle_outline;
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 16),
      label: Text(text),
    );
  }

  Future<void> _loadInvoices({String? reselectId}) async {
    final repository = widget.repository;
    if (repository == null) {
      return;
    }
    final epoch = ++_loadEpoch;
    final requestedStore = widget.membership.storeId;
    final requestedUser = widget.user.id;
    setState(() {
      _invoices = null;
      _listError = null;
    });

    final result = await repository.getRecentPurchaseInvoices(
      context: _context,
    );
    if (!mounted ||
        epoch != _loadEpoch ||
        requestedStore != widget.membership.storeId ||
        requestedUser != widget.user.id) {
      return;
    }
    if (result is FailureResult<List<PurchaseInvoiceSummary>>) {
      setState(() {
        _listError = result.failure.message;
        _invoices = const <PurchaseInvoiceSummary>[];
      });
      return;
    }

    final invoices = (result as Success<List<PurchaseInvoiceSummary>>).value;
    setState(() {
      _invoices = invoices;
      _listError = null;
    });
    final target = reselectId ?? _selectedInvoiceId;
    if (target != null && invoices.any((invoice) => invoice.id == target)) {
      await _selectInvoice(target);
    } else if (target != null) {
      setState(() {
        _selectedInvoiceId = null;
        _document = null;
        _documentError = null;
      });
    }
  }

  Future<void> _selectInvoice(String invoiceId) async {
    final repository = widget.repository;
    if (repository == null) {
      return;
    }
    final epoch = ++_loadEpoch;
    final requestedStore = widget.membership.storeId;
    final requestedUser = widget.user.id;
    setState(() {
      _selectedInvoiceId = invoiceId;
      _document = null;
      _documentError = null;
    });

    final result = await repository.getPurchaseInvoiceDocument(
      context: _context,
      purchaseId: invoiceId,
    );
    if (!mounted ||
        epoch != _loadEpoch ||
        requestedStore != widget.membership.storeId ||
        requestedUser != widget.user.id ||
        _selectedInvoiceId != invoiceId) {
      return;
    }
    if (result is FailureResult<PurchaseInvoiceDocument>) {
      setState(() => _documentError = result.failure.message);
      return;
    }
    setState(() {
      _document = (result as Success<PurchaseInvoiceDocument>).value;
      _documentError = null;
    });
  }

  Future<void> _startPartialReturn(PurchaseInvoiceDocument document) async {
    final invoice = document.invoice;
    final lines = document.lines
        .where((line) => line.remainingQuantityMilliUnits > 0)
        .toList(growable: false);
    if (lines.isEmpty) {
      _showMessage('لا توجد كمية متبقية قابلة للإرجاع.');
      return;
    }

    final draft = await showDialog<_PurchaseReturnDraft>(
      context: context,
      builder: (_) => _PurchaseReturnQuantityDialog(
        invoiceId: invoice.id,
        lines: lines,
      ),
    );
    if (!mounted || draft == null) {
      return;
    }

    final now = DateTime.now().toUtc();
    final returnId =
        'purchase-return-${invoice.id}-${now.microsecondsSinceEpoch}';
    final command = PurchaseReturn(
      id: returnId,
      storeId: widget.membership.storeId,
      idempotencyKey: IdempotencyKey(returnId),
      originalPurchaseId: invoice.id,
      postedAt: now,
      reason: draft.reason.isEmpty ? null : draft.reason,
      lines: draft.lines,
    );
    _pendingReturns[invoice.id] = command;
    await _submitReturn(invoice, command);
  }

  Future<void> _startRemainingReturn(
    PurchaseInvoiceDocument document,
  ) async {
    final invoice = document.invoice;
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _PurchaseReturnReasonDialog(
        invoiceId: invoice.id,
        isPartial: invoice.isPartiallyReturned,
      ),
    );
    if (!mounted || reason == null) {
      return;
    }

    final now = DateTime.now().toUtc();
    final returnId =
        'purchase-return-${invoice.id}-${now.microsecondsSinceEpoch}';
    final command = PurchaseReturn(
      id: returnId,
      storeId: widget.membership.storeId,
      idempotencyKey: IdempotencyKey(returnId),
      originalPurchaseId: invoice.id,
      postedAt: now,
      reason: reason.isEmpty ? null : reason,
    );
    _pendingReturns[invoice.id] = command;
    await _submitReturn(invoice, command);
  }

  Future<void> _submitReturn(
    PurchaseInvoiceSummary invoice,
    PurchaseReturn command,
  ) async {
    final repository = widget.repository;
    if (repository == null || _postingInvoiceId != null) {
      return;
    }

    final requestedStore = widget.membership.storeId;
    final requestedUser = widget.user.id;
    setState(() => _postingInvoiceId = invoice.id);
    try {
      final result = await repository.postPurchaseReturn(
        context: _context,
        purchaseReturn: command,
        accounts: _postingAccounts(invoice),
      );
      if (!mounted ||
          requestedStore != widget.membership.storeId ||
          requestedUser != widget.user.id) {
        return;
      }
      if (result is FailureResult<PurchaseReturnPostingResult>) {
        if (result.failure is! InfrastructureFailure) {
          _pendingReturns.remove(invoice.id);
        }
        _showMessage(
          'تعذر ترحيل مردود المشتريات: ${result.failure.message}',
        );
        return;
      }

      final posted = (result as Success<PurchaseReturnPostingResult>).value;
      _pendingReturns.remove(invoice.id);
      final variance = Money(
        minorUnits: posted.valuationVarianceMinorUnits.abs(),
        currency: invoice.total.currency,
      );
      if (posted.alreadyReturned) {
        _showMessage('تم تأكيد نفس مردود المشتريات السابق دون تكراره.');
      } else if (posted.valuationVarianceMinorUnits == 0) {
        _showMessage(
          posted.returnStatus == 'full'
              ? 'تم إرجاع فاتورة الشراء بالكامل.'
              : 'تم ترحيل مردود المشتريات الجزئي بنجاح.',
        );
      } else {
        _showMessage(
          'تم ترحيل المردود. فرق التقييم ${variance.formatted} '
          'سُجل على الحساب 5200.',
        );
      }
      await _loadInvoices(reselectId: invoice.id);
    } catch (_) {
      if (mounted) {
        _showMessage(
          'تعذر التأكد من نتيجة المردود. أعد المحاولة من نفس الفاتورة '
          'ليُستخدم نفس الطلب حرفيًا.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _postingInvoiceId = null);
      }
    }
  }

  PurchaseReturnPostingAccounts _postingAccounts(
    PurchaseInvoiceSummary invoice,
  ) {
    String? settlementAccountId;
    switch (invoice.paymentMethod) {
      case 'cash':
        settlementAccountId = _cashAccountId;
      case 'bank':
        settlementAccountId = _bankAccountId;
      case 'card':
        settlementAccountId = _cardAccountId;
      case 'credit':
        settlementAccountId = null;
    }
    return PurchaseReturnPostingAccounts(
      settlementAccountId: settlementAccountId,
      supplierPayableAccountId:
          invoice.paymentMethod == 'credit' ? _supplierPayableAccountId : null,
      inventoryAccountId: _inventoryAccountId,
      inputTaxAccountId: invoice.tax.isZero ? null : _inputTaxAccountId,
      purchaseReturnVarianceAccountId: _purchaseReturnVarianceAccountId,
    );
  }

  String _paymentLabel(String value) {
    switch (value) {
      case 'cash':
        return 'نقدي';
      case 'bank':
        return 'بنك';
      case 'card':
        return 'بطاقة';
      case 'credit':
        return 'آجل';
      default:
        return value;
    }
  }

  String _dateLabel(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
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

class _PurchaseReturnReasonDialog extends StatefulWidget {
  const _PurchaseReturnReasonDialog({
    required this.invoiceId,
    required this.isPartial,
  });

  final String invoiceId;
  final bool isPartial;

  @override
  State<_PurchaseReturnReasonDialog> createState() =>
      _PurchaseReturnReasonDialogState();
}

class _PurchaseReturnReasonDialogState
    extends State<_PurchaseReturnReasonDialog> {
  late final TextEditingController _reasonController;

  @override
  void initState() {
    super.initState();
    _reasonController = TextEditingController(
      text: widget.isPartial
          ? 'إرجاع المتبقي من فاتورة الشراء ${widget.invoiceId}'
          : 'إرجاع كامل لفاتورة الشراء ${widget.invoiceId}',
    );
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.isPartial
            ? 'تأكيد إرجاع كل الكمية المتبقية'
            : 'تأكيد إرجاع فاتورة الشراء بالكامل',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'سيتم احتساب رد المورد من الفاتورة الأصلية، بينما يخرج '
            'المخزون بقيمته الدفترية الحالية. أي فرق تقييم يظهر في '
            'الحساب 5200 بشكل صريح.',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('purchase-return-full-reason'),
            controller: _reasonController,
            maxLength: 250,
            decoration: const InputDecoration(labelText: 'سبب المردود'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(
            _reasonController.text.trim(),
          ),
          icon: const Icon(Icons.undo),
          label: const Text('تأكيد المردود'),
        ),
      ],
    );
  }
}

class _PurchaseReturnDraft {
  const _PurchaseReturnDraft({
    required this.lines,
    required this.reason,
  });

  final List<PurchaseReturnLineRequest> lines;
  final String reason;
}

class _PurchaseReturnQuantityDialog extends StatefulWidget {
  const _PurchaseReturnQuantityDialog({
    required this.invoiceId,
    required this.lines,
  });

  final String invoiceId;
  final List<PurchaseInvoiceLineSummary> lines;

  @override
  State<_PurchaseReturnQuantityDialog> createState() =>
      _PurchaseReturnQuantityDialogState();
}

class _PurchaseReturnQuantityDialogState
    extends State<_PurchaseReturnQuantityDialog> {
  late final Map<String, TextEditingController> _quantityControllers;
  late final TextEditingController _reasonController;
  String? _validationMessage;

  @override
  void initState() {
    super.initState();
    _quantityControllers = <String, TextEditingController>{
      for (final line in widget.lines) line.id: TextEditingController(),
    };
    _reasonController = TextEditingController(
      text: 'مردود مشتريات جزئي للفاتورة ${widget.invoiceId}',
    );
  }

  @override
  void dispose() {
    for (final controller in _quantityControllers.values) {
      controller.dispose();
    }
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('مردود مشتريات جزئي'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'أدخل كمية الإرجاع فقط. سعر الشراء والخصم والضريبة '
                  'وقيمة المخزون لا يمكن تعديلها من الشاشة.',
                ),
                const SizedBox(height: 12),
                for (final line in widget.lines) _buildLine(line),
                TextField(
                  key: const ValueKey('purchase-return-reason'),
                  controller: _reasonController,
                  maxLength: 250,
                  decoration: const InputDecoration(labelText: 'سبب المردود'),
                ),
                if (_validationMessage != null)
                  Text(
                    _validationMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.undo),
            label: const Text('ترحيل المردود الجزئي'),
          ),
        ],
      ),
    );
  }

  Widget _buildLine(PurchaseInvoiceLineSummary line) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              line.description,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'المشترى: '
              '${Quantity.fromMilliUnits(line.quantityMilliUnits).formatted} • '
              'مرتجع سابقًا: '
              '${Quantity.fromMilliUnits(line.returnedQuantityMilliUnits).formatted} • '
              'المتبقي: '
              '${Quantity.fromMilliUnits(line.remainingQuantityMilliUnits).formatted} '
              "${line.unitName ?? ''}",
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey('purchase-return-qty-${line.id}'),
                    controller: _quantityControllers[line.id],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'كمية الإرجاع',
                      suffixText: line.unitName,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    _quantityControllers[line.id]!.text =
                        Quantity.fromMilliUnits(
                      line.remainingQuantityMilliUnits,
                    ).formatted;
                  },
                  child: const Text('كل المتبقي'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    final requestedLines = <PurchaseReturnLineRequest>[];
    for (final line in widget.lines) {
      final raw = _quantityControllers[line.id]!.text.trim();
      if (raw.isEmpty) {
        continue;
      }

      Quantity quantity;
      try {
        quantity = Quantity.fromString(raw);
      } catch (_) {
        setState(() {
          _validationMessage =
              'الكمية المدخلة للصنف ${line.description} غير صحيحة.';
        });
        return;
      }
      if (quantity.milliUnits <= 0) {
        continue;
      }
      if (quantity.milliUnits > line.remainingQuantityMilliUnits) {
        setState(() {
          _validationMessage =
              'كمية ${line.description} تتجاوز الكمية المتبقية.';
        });
        return;
      }
      requestedLines.add(
        PurchaseReturnLineRequest(
          lineId: line.id,
          quantityMilliUnits: quantity.milliUnits,
        ),
      );
    }

    if (requestedLines.isEmpty) {
      setState(() {
        _validationMessage = 'أدخل كمية موجبة لصنف واحد على الأقل.';
      });
      return;
    }

    Navigator.of(context).pop(
      _PurchaseReturnDraft(
        lines: requestedLines,
        reason: _reasonController.text.trim(),
      ),
    );
  }
}
