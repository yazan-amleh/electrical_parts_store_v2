import 'package:flutter/material.dart';

import '../../../core/errors/failure.dart';
import '../../../core/idempotency/idempotency_key.dart';
import '../../../core/money/money.dart';
import '../../../core/quantity/quantity.dart';
import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../../inventory/domain/entities/product.dart';
import '../../inventory/domain/repositories/product_repository.dart';
import '../../parties/domain/entities/party.dart';
import '../../parties/domain/enums/party_type.dart';
import '../../parties/domain/repositories/party_repository.dart';
import '../../purchases/domain/entities/purchase_posting_plan.dart';
import '../../purchases/domain/enums/purchase_payment_method.dart';
import '../domain/entities/purchase_order.dart';
import '../domain/entities/purchase_order_line.dart';
import '../domain/entities/purchase_order_receipt.dart';
import '../domain/enums/purchase_order_status.dart';
import '../domain/repositories/purchase_order_repository.dart';

class PurchaseOrdersPage extends StatefulWidget {
  const PurchaseOrdersPage({
    required this.repository,
    required this.productRepository,
    required this.partyRepository,
    required this.user,
    required this.membership,
    super.key,
  });

  final PurchaseOrderRepository? repository;
  final ProductRepository? productRepository;
  final PartyRepository? partyRepository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<PurchaseOrdersPage> createState() => _PurchaseOrdersPageState();
}

class _PurchaseOrdersPageState extends State<PurchaseOrdersPage> {
  final _searchController = TextEditingController();
  List<PurchaseOrder> _orders = const [];
  List<Product> _products = const [];
  List<Party> _suppliers = const [];
  PurchaseOrderStatus? _statusFilter;
  bool _isLoading = true;
  String? _errorMessage;
  final Map<String, _PendingReceipt> _pendingReceipts =
      <String, _PendingReceipt>{};

  StoreContext get _context =>
      StoreContext(storeId: widget.membership.storeId, userId: widget.user.id);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PurchaseOrdersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.id != widget.user.id ||
        oldWidget.membership.storeId != widget.membership.storeId) {
      _orders = const <PurchaseOrder>[];
      _products = const <Product>[];
      _suppliers = const <Party>[];
      _pendingReceipts.clear();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final search = _searchController.text.trim().toLowerCase();
    final orders = _orders.where((order) {
      final matchesSearch = search.isEmpty ||
          order.orderNumber.toLowerCase().contains(search) ||
          order.supplierName.toLowerCase().contains(search);
      final matchesStatus =
          _statusFilter == null || order.status == _statusFilter;
      return matchesSearch && matchesStatus;
    }).toList(growable: false);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _buildToolbar(),
            const SizedBox(height: 12),
            Expanded(child: _buildBody(orders)),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 260,
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: 'بحث في الطلبات',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        DropdownButton<PurchaseOrderStatus?>(
          value: _statusFilter,
          hint: const Text('كل الحالات'),
          items: <DropdownMenuItem<PurchaseOrderStatus?>>[
            const DropdownMenuItem<PurchaseOrderStatus?>(
              value: null,
              child: Text('كل الحالات'),
            ),
            ...PurchaseOrderStatus.values.map(
              (status) => DropdownMenuItem<PurchaseOrderStatus?>(
                value: status,
                child: Text(status.arabicLabel),
              ),
            ),
          ],
          onChanged: (value) => setState(() => _statusFilter = value),
        ),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _load,
          icon: const Icon(Icons.refresh),
          label: const Text('تحديث'),
        ),
        FilledButton.icon(
          onPressed: _isLoading ? null : _createOrder,
          icon: const Icon(Icons.add),
          label: const Text('طلب شراء جديد'),
        ),
      ],
    );
  }

  Widget _buildBody(List<PurchaseOrder> orders) {
    if (widget.repository == null ||
        widget.productRepository == null ||
        widget.partyRepository == null) {
      return const Center(
        child: Text('مستودع طلبات الشراء غير موصول بهذه البيئة.'),
      );
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42),
            const SizedBox(height: 8),
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }
    if (orders.isEmpty) {
      return const Center(child: Text('لا توجد طلبات شراء.'));
    }

    return ListView.separated(
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _buildOrderCard(orders[index]),
    );
  }

  Widget _buildOrderCard(PurchaseOrder order) {
    final color = switch (order.status) {
      PurchaseOrderStatus.pending => Colors.orange,
      PurchaseOrderStatus.completed => Colors.green,
      PurchaseOrderStatus.cancelled => Colors.red,
    };
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .12),
          child: Icon(Icons.playlist_add_check, color: color),
        ),
        title: Text('${order.orderNumber} • ${order.supplierName}'),
        subtitle: Text(
          '${order.status.arabicLabel} • ${order.lines.length} أصناف • '
          '${order.total.formatted}',
        ),
        trailing: const Icon(Icons.chevron_left),
        onTap: () => _showDetails(order),
      ),
    );
  }

  Future<void> _load() async {
    final repository = widget.repository;
    final productRepository = widget.productRepository;
    final partyRepository = widget.partyRepository;
    if (repository == null ||
        productRepository == null ||
        partyRepository == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final ordersResult = await repository.getPurchaseOrders(context: _context);
    final productsResult = await productRepository.getProducts(
      context: _context,
    );
    final suppliersResult = await partyRepository.getParties(
      context: _context,
      type: PartyType.supplier,
    );
    if (!mounted) {
      return;
    }

    final failures = <Failure>[];
    if (ordersResult is FailureResult<List<PurchaseOrder>>) {
      failures.add(ordersResult.failure);
    }
    if (productsResult is FailureResult<List<Product>>) {
      failures.add(productsResult.failure);
    }
    if (suppliersResult is FailureResult<List<Party>>) {
      failures.add(suppliersResult.failure);
    }
    if (failures.isNotEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = failures.first.message;
      });
      return;
    }

    setState(() {
      _orders = (ordersResult as Success<List<PurchaseOrder>>).value;
      _products = (productsResult as Success<List<Product>>).value;
      _suppliers = (suppliersResult as Success<List<Party>>).value;
      _isLoading = false;
    });
  }

  Future<void> _createOrder() async {
    final repository = widget.repository;
    if (repository == null) {
      return;
    }

    final order = await showDialog<PurchaseOrder>(
      context: context,
      builder: (_) => _CreatePurchaseOrderDialog(
        products: _products,
        suppliers: _suppliers,
        storeId: _context.storeId,
      ),
    );
    if (order == null || !mounted) {
      return;
    }

    final result = await repository.createPurchaseOrder(
      context: _context,
      order: order,
    );
    if (!mounted) {
      return;
    }
    _showResult(
      result,
      successMessage: 'تم حفظ طلب الشراء بدون تغيير الرصيد أو المخزون.',
    );
    if (result is Success<PurchaseOrder>) {
      await _load();
    }
  }

  Future<void> _showDetails(PurchaseOrder order) async {
    final pendingReceipt = _pendingReceipts[order.id];
    final action = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('طلب ${order.orderNumber}'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('المورد: ${order.supplierName}'),
                Text('الحالة: ${order.status.arabicLabel}'),
                Text('الإجمالي: ${order.total.formatted}'),
                if (pendingReceipt != null) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'هناك دفعة استلام سابقة لم تُحسم نتيجتها. '
                    'لا يمكن إنشاء دفعة جديدة قبل إعادة نفس الطلب.',
                  ),
                ],
                const Divider(),
                for (final line in order.lines)
                  ListTile(
                    dense: true,
                    title: Text(line.productName),
                    subtitle: Text(
                      'المطلوب: ${line.quantity.formatted} • '
                      'المستلم: ${line.receivedQuantity.formatted} • '
                      'المتبقي: ${line.remainingQuantity.formatted}',
                    ),
                    trailing: Text(line.unitCost.formatted),
                  ),
                if (order.notes?.trim().isNotEmpty == true) ...[
                  const Divider(),
                  Text('ملاحظات: ${order.notes!}'),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
          if (pendingReceipt != null)
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, 'retry-receipt'),
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة نفس الاستلام'),
            )
          else ...[
            if (order.canCancel)
              TextButton(
                onPressed: () => Navigator.pop(context, 'cancel'),
                child: const Text('إلغاء الطلب'),
              ),
            if (order.canReceive)
              FilledButton(
                onPressed: () => Navigator.pop(context, 'receive'),
                child: Text(
                  order.lines.any(
                    (line) => !line.receivedQuantity.isZero,
                  )
                      ? 'استلام كمية إضافية'
                      : 'استلام وترحيل',
                ),
              ),
          ],
        ],
      ),
    );

    if (!mounted) {
      return;
    }
    if (action == 'cancel') {
      await _cancel(order);
    } else if (action == 'receive') {
      await _receive(order);
    } else if (action == 'retry-receipt' && pendingReceipt != null) {
      await _submitReceipt(order, pendingReceipt);
    }
  }

  Future<void> _cancel(PurchaseOrder order) async {
    final repository = widget.repository;
    if (repository == null) {
      return;
    }
    if (_pendingReceipts.containsKey(order.id)) {
      _showMessage(
        'لا يمكن إلغاء الطلب قبل حسم دفعة الاستلام المعلقة.',
      );
      return;
    }
    final hasReceipts = order.lines.any(
      (line) => !line.receivedQuantity.isZero,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إلغاء طلب الشراء؟'),
        content: Text(
          hasReceipts
              ? 'سيتم إلغاء الكمية المتبقية فقط. الكميات التي تم '
                  'استلامها وترحيلها سابقًا ستبقى كما هي.'
              : 'سيتم إلغاء الطلب فقط، ولن يتغير المخزون أو رصيد المورد.',
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
    if (confirmed != true || !mounted) {
      return;
    }

    final result = await repository.cancelPurchaseOrder(
      context: _context,
      orderId: order.id,
    );
    if (!mounted) {
      return;
    }
    _showResult(
      result,
      successMessage: hasReceipts
          ? 'تم إلغاء الكمية المتبقية من طلب الشراء.'
          : 'تم إلغاء طلب الشراء.',
    );
    if (result is Success<void>) {
      await _load();
    }
  }

  Future<void> _receive(PurchaseOrder order) async {
    final repository = widget.repository;
    if (repository == null) {
      return;
    }
    final pending = _pendingReceipts[order.id];
    if (pending != null) {
      await _submitReceipt(order, pending);
      return;
    }

    final draft = await showDialog<_ReceiveDraft>(
      context: context,
      builder: (_) => _ReceivePurchaseOrderDialog(order: order),
    );
    if (draft == null || !mounted) {
      return;
    }

    final accounts = PurchasePostingAccounts(
      settlementAccountId: draft.paymentMethod == PurchasePaymentMethod.credit
          ? null
          : switch (draft.paymentMethod) {
              PurchasePaymentMethod.cash => '1110',
              PurchasePaymentMethod.bank => '1121',
              PurchasePaymentMethod.card => '1160',
              PurchasePaymentMethod.credit => null,
            },
      inventoryAccountId: '1150',
      supplierPayableAccountId:
          draft.paymentMethod == PurchasePaymentMethod.credit ? '2110' : null,
      inputTaxAccountId: draft.taxMinorUnits > 0 ? '1170' : null,
    );
    final now = DateTime.now().toUtc();
    final receiptId =
        'po-receipt-${order.id}-${now.microsecondsSinceEpoch}';
    final receipt = PurchaseOrderReceiptRequest(
      receiptId: receiptId,
      idempotencyKey: IdempotencyKey(receiptId),
      postedAt: now,
      lines: draft.lines,
    );
    final pendingReceipt = _PendingReceipt(
      receipt: receipt,
      paymentMethod: draft.paymentMethod,
      accounts: accounts,
      taxMinorUnits: draft.taxMinorUnits,
    );
    _pendingReceipts[order.id] = pendingReceipt;
    await _submitReceipt(order, pendingReceipt);
  }

  Future<void> _submitReceipt(
    PurchaseOrder order,
    _PendingReceipt pending,
  ) async {
    final repository = widget.repository;
    if (repository == null) {
      return;
    }

    final result = await repository.receivePurchaseOrder(
      context: _context,
      order: order,
      receipt: pending.receipt,
      paymentMethod: pending.paymentMethod,
      accounts: pending.accounts,
      taxMinorUnits: pending.taxMinorUnits,
    );
    if (!mounted) {
      return;
    }

    if (result is FailureResult<PurchaseOrderReceipt>) {
      final keepPending = result.failure is InfrastructureFailure ||
          result.failure is QueuedFailure;
      if (!keepPending) {
        _pendingReceipts.remove(order.id);
      }
      _showMessage(
        result.failure is QueuedFailure
            ? 'تم حفظ نفس دفعة الاستلام للطابور. '
                'لن يسمح النظام بإنشاء دفعة أخرى حتى تُحسم هذه العملية.'
            : result.failure.message,
      );
      return;
    }

    _pendingReceipts.remove(order.id);
    final receipt = (result as Success<PurchaseOrderReceipt>).value;
    _showMessage(
      receipt.completed
          ? 'تم استلام آخر الكميات واكتمال طلب الشراء.'
          : 'تم ترحيل الاستلام الجزئي، والطلب ما زال مفتوحًا.',
    );
    await _load();
  }

  void _showResult<T>(Result<T> result, {required String successMessage}) {
    final message = result is FailureResult<T>
        ? result.failure is QueuedFailure
            ? 'تم حفظ العملية للطابور وستُنفذ عند عودة الاتصال.'
            : result.failure.message
        : successMessage;
    _showMessage(message);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

class _PendingReceipt {
  const _PendingReceipt({
    required this.receipt,
    required this.paymentMethod,
    required this.accounts,
    required this.taxMinorUnits,
  });

  final PurchaseOrderReceiptRequest receipt;
  final PurchasePaymentMethod paymentMethod;
  final PurchasePostingAccounts accounts;
  final int taxMinorUnits;
}

class _ReceiveDraft {
  const _ReceiveDraft({
    required this.paymentMethod,
    required this.taxMinorUnits,
    required this.lines,
  });

  final PurchasePaymentMethod paymentMethod;
  final int taxMinorUnits;
  final List<PurchaseOrderReceiptLine> lines;
}

class _ReceivePurchaseOrderDialog extends StatefulWidget {
  const _ReceivePurchaseOrderDialog({required this.order});

  final PurchaseOrder order;

  @override
  State<_ReceivePurchaseOrderDialog> createState() =>
      _ReceivePurchaseOrderDialogState();
}

class _ReceivePurchaseOrderDialogState
    extends State<_ReceivePurchaseOrderDialog> {
  final _taxController = TextEditingController();
  late final Map<String, TextEditingController> _quantityControllers;
  PurchasePaymentMethod _paymentMethod = PurchasePaymentMethod.cash;
  String? _error;

  List<PurchaseOrderLine> get _remainingLines => widget.order.lines
      .where((line) => !line.remainingQuantity.isZero)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _quantityControllers = <String, TextEditingController>{
      for (final line in _remainingLines)
        line.id: TextEditingController(text: line.remainingQuantity.formatted),
    };
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('استلام طلب الشراء'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final line in _remainingLines) ...[
                Text(
                  line.productName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'المطلوب: ${line.quantity.formatted} • '
                  'المستلم: ${line.receivedQuantity.formatted} • '
                  'المتبقي: ${line.remainingQuantity.formatted}',
                ),
                const SizedBox(height: 6),
                TextField(
                  key: ValueKey('po-receipt-qty-${line.id}'),
                  controller: _quantityControllers[line.id],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'كمية الاستلام',
                    suffixText: line.unitName,
                  ),
                ),
                const Divider(height: 24),
              ],
              DropdownButtonFormField<PurchasePaymentMethod>(
                value: _paymentMethod,
                decoration: const InputDecoration(labelText: 'طريقة الدفع'),
                items: PurchasePaymentMethod.values
                    .map(
                      (method) => DropdownMenuItem(
                        value: method,
                        child: Text(_paymentLabel(method)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _paymentMethod = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _taxController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'ضريبة المدخلات لهذه الدفعة (اختياري)',
                  hintText: '0.00',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('رجوع'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('استلام وترحيل'),
        ),
      ],
    );
  }

  void _submit() {
    final tax = _parseMinorUnits(_taxController.text);
    if (tax == null) {
      setState(() => _error = 'قيمة الضريبة غير صحيحة.');
      return;
    }

    final lines = <PurchaseOrderReceiptLine>[];
    for (final line in _remainingLines) {
      final raw = _quantityControllers[line.id]!.text.trim();
      if (raw.isEmpty) {
        continue;
      }
      final quantity = _parseQuantity(raw);
      if (quantity == null || quantity.isNegative) {
        setState(() => _error = 'كمية ${line.productName} غير صحيحة.');
        return;
      }
      if (quantity.isZero) {
        continue;
      }
      if (quantity.milliUnits > line.remainingQuantity.milliUnits) {
        setState(
          () => _error =
              'كمية ${line.productName} تتجاوز الكمية المتبقية.',
        );
        return;
      }
      lines.add(
        PurchaseOrderReceiptLine(
          lineId: line.id,
          quantityMilliUnits: quantity.milliUnits,
        ),
      );
    }
    if (lines.isEmpty) {
      setState(() => _error = 'أدخل كمية موجبة لسطر واحد على الأقل.');
      return;
    }

    Navigator.pop(
      context,
      _ReceiveDraft(
        paymentMethod: _paymentMethod,
        taxMinorUnits: tax,
        lines: lines,
      ),
    );
  }

  @override
  void dispose() {
    _taxController.dispose();
    for (final controller in _quantityControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }
}

class _CreatePurchaseOrderDialog extends StatefulWidget {
  const _CreatePurchaseOrderDialog({
    required this.products,
    required this.suppliers,
    required this.storeId,
  });

  final List<Product> products;
  final List<Party> suppliers;
  final String storeId;

  @override
  State<_CreatePurchaseOrderDialog> createState() =>
      _CreatePurchaseOrderDialogState();
}

class _CreatePurchaseOrderDialogState
    extends State<_CreatePurchaseOrderDialog> {
  final _quantityController = TextEditingController(text: '1');
  final _costController = TextEditingController();
  final _notesController = TextEditingController();
  final List<PurchaseOrderLine> _lines = <PurchaseOrderLine>[];
  Party? _supplier;
  Product? _product;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('طلب شراء جديد'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<Party>(
                value: _supplier,
                decoration: const InputDecoration(labelText: 'المورد'),
                items: widget.suppliers
                    .map(
                      (supplier) => DropdownMenuItem(
                        value: supplier,
                        child: Text(supplier.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => setState(() => _supplier = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Product>(
                value: _product,
                decoration: const InputDecoration(labelText: 'الصنف'),
                items: widget.products
                    .where((product) => !product.isService)
                    .map(
                      (product) => DropdownMenuItem(
                        value: product,
                        child: Text(product.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  setState(() {
                    _product = value;
                    if (value != null) {
                      _costController.text =
                          (value.purchasePrice.minorUnits / 100)
                              .toStringAsFixed(2);
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _quantityController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'الكمية'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _costController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'تكلفة الوحدة',
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _addLine,
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'إضافة الصنف',
                  ),
                ],
              ),
              const Divider(),
              if (_lines.isEmpty)
                const Text('أضف صنفاً واحداً على الأقل.')
              else
                for (final line in _lines)
                  ListTile(
                    dense: true,
                    title: Text(line.productName),
                    subtitle: Text(
                      '${line.quantity.formatted} × ${line.unitCost.formatted}',
                    ),
                    trailing: IconButton(
                      onPressed: () => setState(() => _lines.remove(line)),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
              const SizedBox(height: 8),
              TextField(
                controller: _notesController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'ملاحظات'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('رجوع'),
        ),
        FilledButton(onPressed: _save, child: const Text('حفظ الطلب')),
      ],
    );
  }

  void _addLine() {
    final product = _product;
    if (product == null) {
      _showError('اختر الصنف أولاً.');
      return;
    }
    final quantity = _parseQuantity(_quantityController.text);
    final cost = _parseMoney(
      _costController.text,
      product.purchasePrice.currency,
    );
    if (quantity == null || quantity.isZero || quantity.isNegative) {
      _showError('الكمية غير صحيحة.');
      return;
    }
    if (cost == null || cost.isNegative) {
      _showError('التكلفة غير صحيحة.');
      return;
    }
    if (_lines.any((line) => line.productId == product.id)) {
      _showError('الصنف مضاف مسبقاً.');
      return;
    }

    setState(() {
      _lines.add(
        PurchaseOrderLine(
          id: 'line-${DateTime.now().microsecondsSinceEpoch}',
          productId: product.id,
          productName: product.name,
          quantity: quantity,
          unitFactorToBase: const Quantity.fromMilliUnits(1000),
          unitCost: cost,
          unitId: product.baseUnitId,
          unitName: product.baseUnitName,
        ),
      );
      _product = null;
      _quantityController.text = '1';
      _costController.clear();
    });
  }

  void _save() {
    final supplier = _supplier;
    if (supplier == null) {
      _showError('اختر المورد أولاً.');
      return;
    }
    if (_lines.isEmpty) {
      _showError('أضف صنفاً واحداً على الأقل.');
      return;
    }

    final id = 'po-${DateTime.now().microsecondsSinceEpoch}';
    Navigator.pop(
      context,
      PurchaseOrder(
        id: id,
        storeId: widget.storeId,
        orderNumber: 'PO-${DateTime.now().millisecondsSinceEpoch}',
        supplierId: supplier.id,
        supplierName: supplier.name,
        orderedAt: DateTime.now().toUtc(),
        lines: _lines,
        status: PurchaseOrderStatus.pending,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _costController.dispose();
    _notesController.dispose();
    super.dispose();
  }
}

int? _parseMinorUnits(String raw) {
  final normalized = raw.trim().replaceAll(',', '.');
  if (normalized.isEmpty) {
    return 0;
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
  final fraction = parts.length == 1 || parts[1].isEmpty
      ? 0
      : int.parse(parts[1].padRight(2, '0'));
  return int.parse(parts.first) * 100 + fraction;
}

Money? _parseMoney(String raw, String currency) {
  final minorUnits = _parseMinorUnits(raw);
  return minorUnits == null
      ? null
      : Money(minorUnits: minorUnits, currency: currency);
}

Quantity? _parseQuantity(String raw) {
  try {
    return Quantity.fromString(raw);
  } on ArgumentError {
    return null;
  }
}

String _paymentLabel(PurchasePaymentMethod method) {
  switch (method) {
    case PurchasePaymentMethod.cash:
      return 'نقداً';
    case PurchasePaymentMethod.bank:
      return 'بنك';
    case PurchasePaymentMethod.card:
      return 'بطاقة';
    case PurchasePaymentMethod.credit:
      return 'آجل';
  }
}
