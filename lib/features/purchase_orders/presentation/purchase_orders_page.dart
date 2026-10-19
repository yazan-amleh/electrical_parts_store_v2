import 'package:flutter/material.dart';

import '../../../core/errors/failure.dart';
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

  StoreContext get _context => StoreContext(
        storeId: widget.membership.storeId,
        userId: widget.user.id,
      );

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
          backgroundColor: color.withOpacity(.12),
          child: Icon(Icons.playlist_add_check, color: color),
        ),
        title: Text(order.orderNumber + ' • ' + order.supplierName),
        subtitle: Text(
          order.status.arabicLabel +
              ' • ' +
              order.lines.length.toString() +
              ' أصناف • ' +
              order.total.formatted,
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
    final productsResult = await productRepository.getProducts(context: _context);
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
    final action = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('طلب ' + order.orderNumber),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('المورد: ' + order.supplierName),
                Text('الحالة: ' + order.status.arabicLabel),
                Text('الإجمالي: ' + order.total.formatted),
                const Divider(),
                for (final line in order.lines)
                  ListTile(
                    dense: true,
                    title: Text(line.productName),
                    subtitle: Text(
                      line.quantity.formatted + ' × ' + line.unitCost.formatted,
                    ),
                    trailing: Text(line.total.formatted),
                  ),
                if (order.notes?.trim().isNotEmpty == true) ...[
                  const Divider(),
                  Text('ملاحظات: ' + order.notes!),
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
          if (order.canCancel)
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('إلغاء الطلب'),
            ),
          if (order.canReceive)
            FilledButton(
              onPressed: () => Navigator.pop(context, 'receive'),
              child: const Text('استلام وترحيل'),
            ),
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
    }
  }

  Future<void> _cancel(PurchaseOrder order) async {
    final repository = widget.repository;
    if (repository == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إلغاء طلب الشراء؟'),
        content: const Text(
          'سيتم إلغاء الطلب فقط، ولن يتغير المخزون أو رصيد المورد.',
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
    _showResult(result, successMessage: 'تم إلغاء طلب الشراء.');
    if (result is Success<void>) {
      await _load();
    }
  }

  Future<void> _receive(PurchaseOrder order) async {
    final repository = widget.repository;
    if (repository == null) {
      return;
    }

    final draft = await showDialog<_ReceiveDraft>(
      context: context,
      builder: (_) => const _ReceivePurchaseOrderDialog(),
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
    final result = await repository.receivePurchaseOrder(
      context: _context,
      order: order,
      paymentMethod: draft.paymentMethod,
      accounts: accounts,
      taxMinorUnits: draft.taxMinorUnits,
    );
    if (!mounted) {
      return;
    }
    _showResult(
      result,
      successMessage: 'تم استلام الطلب وترحيل القيد والمخزون.',
    );
    if (result is Success<PurchaseOrderReceipt>) {
      await _load();
    }
  }

  void _showResult<T>(Result<T> result, {required String successMessage}) {
    final message = result is FailureResult<T>
        ? result.failure is QueuedFailure
            ? 'تم حفظ العملية للطابور وستُنفذ عند عودة الاتصال.'
            : result.failure.message
        : successMessage;
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

class _ReceiveDraft {
  const _ReceiveDraft({
    required this.paymentMethod,
    required this.taxMinorUnits,
  });

  final PurchasePaymentMethod paymentMethod;
  final int taxMinorUnits;
}

class _ReceivePurchaseOrderDialog extends StatefulWidget {
  const _ReceivePurchaseOrderDialog();

  @override
  State<_ReceivePurchaseOrderDialog> createState() =>
      _ReceivePurchaseOrderDialogState();
}

class _ReceivePurchaseOrderDialogState
    extends State<_ReceivePurchaseOrderDialog> {
  final _taxController = TextEditingController();
  PurchasePaymentMethod _paymentMethod = PurchasePaymentMethod.cash;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('استلام طلب الشراء'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<PurchasePaymentMethod>(
              initialValue: _paymentMethod,
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
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'ضريبة المدخلات (اختياري)',
                hintText: '0.00',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('رجوع'),
        ),
        FilledButton(
          onPressed: () {
            final tax = _parseMinorUnits(_taxController.text);
            if (tax == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('قيمة الضريبة غير صحيحة.')),
              );
              return;
            }
            Navigator.pop(
              context,
              _ReceiveDraft(
                paymentMethod: _paymentMethod,
                taxMinorUnits: tax,
              ),
            );
          },
          child: const Text('استلام وترحيل'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _taxController.dispose();
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
                initialValue: _supplier,
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
                initialValue: _product,
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
                      line.quantity.formatted +
                          ' × ' +
                          line.unitCost.formatted,
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
        FilledButton(
          onPressed: _save,
          child: const Text('حفظ الطلب'),
        ),
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
          id: 'line-' + DateTime.now().microsecondsSinceEpoch.toString(),
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

    final id = 'po-' + DateTime.now().microsecondsSinceEpoch.toString();
    Navigator.pop(
      context,
      PurchaseOrder(
        id: id,
        storeId: widget.storeId,
        orderNumber: 'PO-' + DateTime.now().millisecondsSinceEpoch.toString(),
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
