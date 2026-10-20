import 'package:flutter/material.dart';

import '../../../../core/idempotency/idempotency_key.dart';
import '../../../../core/money/money.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../../auth/domain/entities/authenticated_user.dart';
import '../../../auth/domain/entities/store_membership.dart';
import '../../../inventory/domain/entities/product.dart';
import '../../../inventory/domain/repositories/product_repository.dart';
import '../../../parties/domain/entities/party.dart';
import '../../../parties/domain/enums/party_type.dart';
import '../../../parties/domain/repositories/party_repository.dart';
import '../../../payments/domain/enums/party_payment_method.dart';
import '../../domain/entities/repair_part.dart';
import '../../domain/entities/repair_payment.dart';
import '../../domain/entities/repair_posting_accounts.dart';
import '../../domain/entities/repair_request.dart';
import '../../domain/enums/device_condition.dart';
import '../../domain/enums/repair_payment_kind.dart';
import '../../domain/enums/repair_priority.dart';
import '../../domain/enums/repair_status.dart';
import '../../domain/repositories/repair_repository.dart';

class RepairsPage extends StatefulWidget {
  const RepairsPage({
    required this.repository,
    required this.productRepository,
    required this.partyRepository,
    required this.user,
    required this.membership,
    super.key,
  });

  final RepairRepository? repository;
  final ProductRepository? productRepository;
  final PartyRepository? partyRepository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<RepairsPage> createState() => _RepairsPageState();
}

class _RepairsPageState extends State<RepairsPage> {
  Future<Result<List<RepairRequest>>>? _future;
  RepairStatus? _filter;

  StoreContext get _storeContext =>
      StoreContext(storeId: widget.membership.storeId, userId: widget.user.id);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    final repository = widget.repository;
    if (repository == null) {
      return;
    }
    _future = repository.getRepairs(context: _storeContext, status: _filter);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _create() async {
    final repository = widget.repository;
    final partyRepository = widget.partyRepository;
    if (repository == null || partyRepository == null) {
      _message('مستودع الصيانة أو العملاء غير متاح.');
      return;
    }
    final result = await partyRepository.getParties(
      context: _storeContext,
      type: PartyType.customer,
    );
    if (!mounted) {
      return;
    }
    if (result is FailureResult<List<Party>>) {
      _message(result.failure.message);
      return;
    }
    final customers = (result as Success<List<Party>>).value;
    if (customers.isEmpty) {
      _message('أضف عميلاً قبل تسجيل طلب صيانة.');
      return;
    }
    final repair = await showDialog<RepairRequest>(
      context: context,
      builder: (_) => _CreateRepairDialog(
        storeId: widget.membership.storeId,
        customers: customers,
      ),
    );
    if (repair == null || !mounted) {
      return;
    }
    final created = await repository.createRepair(
      context: _storeContext,
      repair: repair,
    );
    if (!mounted) {
      return;
    }
    if (created is FailureResult<RepairRequest>) {
      _message(created.failure.message);
    } else {
      _message('تم تسجيل طلب الصيانة.');
      _refresh();
    }
  }

  Future<void> _open(RepairRequest repair) async {
    final repository = widget.repository;
    if (repository == null) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _RepairDialog(
        repository: repository,
        productRepository: widget.productRepository,
        storeContext: _storeContext,
        initialRepair: repair,
      ),
    );
    if (mounted) {
      _refresh();
    }
  }

  void _message(String value) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.repository == null) {
      return const Center(
        child: Text('وحدة الصيانة غير مربوطة بمصدر البيانات.'),
      );
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('الصيانة والإصلاحات'),
          actions: [
            IconButton(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _create,
          icon: const Icon(Icons.add),
          label: const Text('طلب صيانة'),
        ),
        body: Column(
          children: [
            SizedBox(
              height: 56,
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                scrollDirection: Axis.horizontal,
                children: [
                  ChoiceChip(
                    label: const Text('الكل'),
                    selected: _filter == null,
                    onSelected: (_) {
                      setState(() => _filter = null);
                      _refresh();
                    },
                  ),
                  const SizedBox(width: 8),
                  for (final status in RepairStatus.values) ...[
                    ChoiceChip(
                      label: Text(status.arabicLabel),
                      selected: _filter == status,
                      onSelected: (_) {
                        setState(() => _filter = status);
                        _refresh();
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<Result<List<RepairRequest>>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final result = snapshot.data;
                  if (result == null) {
                    return const Center(child: Text('لا توجد بيانات للعرض.'));
                  }
                  if (result is FailureResult<List<RepairRequest>>) {
                    return Center(child: Text(result.failure.message));
                  }
                  final repairs =
                      (result as Success<List<RepairRequest>>).value;
                  if (repairs.isEmpty) {
                    return const Center(
                      child: Text('لا توجد طلبات صيانة بهذه الحالة.'),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async => _refresh(),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: repairs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, index) => _RepairTile(
                        repair: repairs[index],
                        onTap: () => _open(repairs[index]),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RepairTile extends StatelessWidget {
  const _RepairTile({required this.repair, required this.onTap});

  final RepairRequest repair;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          child: Icon(
            repair.status == RepairStatus.delivered
                ? Icons.check
                : Icons.build_outlined,
          ),
        ),
        title: Text(
          '${repair.deviceName} — ${repair.deviceModel}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          'العميل: ${repair.customerId}\n'
          'التسليم: ${_dateText(repair.expectedDeliveryDate)}',
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(repair.status.arabicLabel),
            Text(repair.finalCost.formatted),
          ],
        ),
      ),
    );
  }
}

class _RepairDialog extends StatefulWidget {
  const _RepairDialog({
    required this.repository,
    required this.productRepository,
    required this.storeContext,
    required this.initialRepair,
  });

  final RepairRepository repository;
  final ProductRepository? productRepository;
  final StoreContext storeContext;
  final RepairRequest initialRepair;

  @override
  State<_RepairDialog> createState() => _RepairDialogState();
}

class _RepairDialogState extends State<_RepairDialog> {
  late RepairRequest _repair;
  List<RepairPayment> _payments = const [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repair = widget.initialRepair;
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    final result = await widget.repository.getPayments(
      context: widget.storeContext,
      repairId: _repair.id,
    );
    if (mounted && result is Success<List<RepairPayment>>) {
      setState(() => _payments = result.value);
    }
  }

  Future<void> _reload() async {
    final result = await widget.repository.getRepair(
      context: widget.storeContext,
      repairId: _repair.id,
    );
    if (!mounted) {
      return;
    }
    if (result is Success<RepairRequest>) {
      setState(() => _repair = result.value);
      await _loadPayments();
    } else if (result is FailureResult<RepairRequest>) {
      _setError(result.failure.message);
    }
  }

  Future<void> _status(RepairStatus next) async {
    final result = await _run(
      () => widget.repository.updateRepair(
        context: widget.storeContext,
        repair: _repair.copyWith(status: next),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    if (result is Success<RepairRequest>) {
      setState(() => _repair = result.value);
    }
  }

  Future<void> _addPart() async {
    final productsRepository = widget.productRepository;
    if (productsRepository == null) {
      _setError('مستودع الأصناف غير متاح.');
      return;
    }
    final result = await productsRepository.getProducts(
      context: widget.storeContext,
    );
    if (!mounted) {
      return;
    }
    if (result is FailureResult<List<Product>>) {
      _setError(result.failure.message);
      return;
    }
    final products = (result as Success<List<Product>>)
        .value
        .where((product) => product.isActive && !product.isService)
        .toList(growable: false);
    final part = await showDialog<RepairPart>(
      context: context,
      builder: (_) => _PartDialog(
        products: products,
        currency: _repair.laborCost.currency,
        existingIds: _repair.parts.map((part) => part.productId).toSet(),
      ),
    );
    if (part == null || !mounted) {
      return;
    }
    final updated = await _run(
      () => widget.repository.updateRepair(
        context: widget.storeContext,
        repair: _repair.copyWith(parts: [..._repair.parts, part]),
      ),
    );
    if (mounted && updated is Success<RepairRequest>) {
      setState(() => _repair = updated.value);
    }
  }

  Future<void> _payment(RepairPaymentKind kind) async {
    if (kind == RepairPaymentKind.advance && _repair.isInvoiced) {
      _setError('لا يمكن إضافة دفعة مقدمة بعد الفاتورة.');
      return;
    }
    if (kind == RepairPaymentKind.settlement && !_repair.isInvoiced) {
      _setError('أصدر فاتورة الصيانة أولاً.');
      return;
    }
    final payment = await showDialog<RepairPayment>(
      context: context,
      builder: (_) => _PaymentDialog(
        storeId: widget.storeContext.storeId,
        customerId: _repair.customerId,
        repairId: _repair.id,
        currency: _repair.laborCost.currency,
        kind: kind,
      ),
    );
    if (payment == null || !mounted) {
      return;
    }
    final result = await _run(
      () => widget.repository.postPayment(
        context: widget.storeContext,
        payment: payment,
        accounts: const RepairPostingAccounts(),
      ),
    );
    if (mounted && result is Success<RepairPayment>) {
      await _reload();
    }
  }

  Future<void> _deliver() async {
    if (_repair.isInvoiced || _repair.status == RepairStatus.cancelled) {
      return;
    }
    final result = await _run(
      () => widget.repository.deliverRepair(
        context: widget.storeContext,
        repairId: _repair.id,
        idempotencyKey: 'repair-delivery-${_repair.id}',
        postedAt: DateTime.now().toUtc(),
        accounts: const RepairPostingAccounts(),
      ),
    );
    if (mounted && result is Success<RepairRequest>) {
      setState(() => _repair = result.value);
      await _loadPayments();
    }
  }

  Future<Result<T>?> _run<T>(Future<Result<T>> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await action();
      if (mounted && result is FailureResult<T>) {
        _setError(result.failure.message);
      }
      return result;
    } catch (error) {
      if (mounted) {
        _setError(error.toString());
      }
      return null;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _setError(String message) {
    if (mounted) {
      setState(() => _error = message);
    }
  }

  List<RepairStatus> get _nextStatuses {
    switch (_repair.status) {
      case RepairStatus.received:
        return const [RepairStatus.diagnosing, RepairStatus.cancelled];
      case RepairStatus.diagnosing:
        return const [RepairStatus.inProgress, RepairStatus.cancelled];
      case RepairStatus.inProgress:
        return const [RepairStatus.ready, RepairStatus.cancelled];
      case RepairStatus.ready:
        return const [RepairStatus.inProgress, RepairStatus.cancelled];
      case RepairStatus.delivered:
      case RepairStatus.cancelled:
        return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = !_busy &&
        !_repair.isInvoiced &&
        _repair.status != RepairStatus.cancelled;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.build_outlined),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${_repair.deviceName} — ${_repair.deviceModel}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              onPressed: _busy ? null : _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        content: SizedBox(
          width: 700,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  _Banner(text: _error!),
                  const SizedBox(height: 8),
                ],
                Card(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 20,
                      runSpacing: 8,
                      children: [
                        Text('الحالة: ${_repair.status.arabicLabel}'),
                        Text('العميل: ${_repair.customerId}'),
                        Text('الأولوية: ${_repair.priority.arabicLabel}'),
                        Text('الإجمالي: ${_repair.finalCost.formatted}'),
                        Text('المتبقي: ${_repair.outstanding.formatted}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _repair.problemDescription.isEmpty
                      ? 'لا يوجد وصف للعطل.'
                      : _repair.problemDescription,
                ),
                if (_repair.serialNumber.isNotEmpty)
                  Text('الرقم التسلسلي: ${_repair.serialNumber}'),
                const SizedBox(height: 12),
                Text(
                  'تغيير الحالة',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final next in _nextStatuses)
                      ActionChip(
                        label: Text(next.arabicLabel),
                        onPressed: canEdit ? () => _status(next) : null,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'القطع المستخدمة',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      onPressed: canEdit ? _addPart : null,
                      icon: const Icon(Icons.add_circle_outline),
                      tooltip: 'إضافة قطعة',
                    ),
                  ],
                ),
                if (_repair.parts.isEmpty)
                  const Text('لا توجد قطع مضافة.')
                else
                  for (final part in _repair.parts)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(part.productName),
                      subtitle: Text(
                        '${part.quantity.formatted} × ${part.unitPrice.formatted}',
                      ),
                      trailing: Text(part.totalPrice.formatted),
                    ),
                const Divider(),
                Text(
                  'المدفوعات',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text('مقدمة: ${_repair.advancePaid.formatted}'),
                Text('بعد الفاتورة: ${_repair.paid.formatted}'),
                if (_payments.isNotEmpty)
                  for (final payment in _payments)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(payment.kind.arabicLabel),
                      subtitle: Text(
                        '${_paymentLabel(payment.paymentMethod)} — '
                        '${_dateText(payment.postedAt)}',
                      ),
                      trailing: Text(payment.amount.formatted),
                    ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: canEdit
                          ? () => _payment(RepairPaymentKind.advance)
                          : null,
                      child: const Text('دفعة مقدمة'),
                    ),
                    OutlinedButton(
                      onPressed: !_busy && _repair.isInvoiced
                          ? () => _payment(RepairPaymentKind.settlement)
                          : null,
                      child: const Text('دفعة على الفاتورة'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
          ),
          if (!_repair.isInvoiced && _repair.status != RepairStatus.cancelled)
            FilledButton.icon(
              onPressed: _busy ? null : _deliver,
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('فاتورة وتسليم'),
            ),
          if (_busy)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}

class _CreateRepairDialog extends StatefulWidget {
  const _CreateRepairDialog({required this.storeId, required this.customers});

  final String storeId;
  final List<Party> customers;

  @override
  State<_CreateRepairDialog> createState() => _CreateRepairDialogState();
}

class _CreateRepairDialogState extends State<_CreateRepairDialog> {
  final _formKey = GlobalKey<FormState>();
  final _device = TextEditingController();
  final _model = TextEditingController();
  final _problem = TextEditingController();
  final _estimated = TextEditingController();
  final _labor = TextEditingController();
  final _serial = TextEditingController();
  final _notes = TextEditingController();
  final _requiredParts = TextEditingController();
  late String _customerId;
  RepairPriority _priority = RepairPriority.normal;
  DeviceCondition _condition = DeviceCondition.notWorking;
  DateTime _expectedDate = DateTime.now().add(const Duration(days: 7));

  @override
  void initState() {
    super.initState();
    _customerId = widget.customers.first.id;
  }

  @override
  void dispose() {
    _device.dispose();
    _model.dispose();
    _problem.dispose();
    _estimated.dispose();
    _labor.dispose();
    _serial.dispose();
    _notes.dispose();
    _requiredParts.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: _expectedDate,
    );
    if (date != null && mounted) {
      setState(() => _expectedDate = date);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    try {
      final now = DateTime.now().toUtc();
      final id = 'repair-${now.microsecondsSinceEpoch}';
      final repair = RepairRequest(
        id: id,
        storeId: widget.storeId,
        idempotencyKey: IdempotencyKey(id),
        customerId: _customerId,
        deviceName: _device.text.trim(),
        deviceModel: _model.text.trim(),
        problemDescription: _problem.text.trim(),
        createdAt: now,
        receivedAt: now,
        expectedDeliveryDate: _expectedDate.toUtc(),
        estimatedCost: Money(minorUnits: _minor(_estimated.text)),
        laborCost: Money(minorUnits: _minor(_labor.text)),
        technicianNotes: _notes.text.trim(),
        serialNumber: _serial.text.trim(),
        priority: _priority,
        deviceCondition: _condition,
        requiredParts: _requiredParts.text
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList(growable: false),
      );
      Navigator.of(context).pop(repair);
    } catch (error) {
      setState(() {});
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('استلام جهاز للصيانة'),
        content: SizedBox(
          width: 640,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    value: _customerId,
                    decoration: const InputDecoration(labelText: 'العميل'),
                    items: [
                      for (final customer in widget.customers)
                        DropdownMenuItem(
                          value: customer.id,
                          child: Text(customer.name),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _customerId = value);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  _field(_device, 'نوع الجهاز', requiredField: true),
                  const SizedBox(height: 10),
                  _field(_model, 'الموديل', requiredField: true),
                  const SizedBox(height: 10),
                  _field(_problem, 'وصف العطل', maxLines: 3),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          _estimated,
                          'التكلفة التقديرية',
                          keyboardType: TextInputType.number,
                          validator: _amountValidator,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _field(
                          _labor,
                          'أجرة العمل',
                          keyboardType: TextInputType.number,
                          validator: _amountValidator,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<RepairPriority>(
                          value: _priority,
                          decoration: const InputDecoration(
                            labelText: 'الأولوية',
                          ),
                          items: [
                            for (final value in RepairPriority.values)
                              DropdownMenuItem(
                                value: value,
                                child: Text(value.arabicLabel),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _priority = value);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<DeviceCondition>(
                          value: _condition,
                          decoration: const InputDecoration(
                            labelText: 'حالة الجهاز',
                          ),
                          items: [
                            for (final value in DeviceCondition.values)
                              DropdownMenuItem(
                                value: value,
                                child: Text(value.arabicLabel),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _condition = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'موعد التسليم المتوقع',
                      ),
                      child: Text(_dateText(_expectedDate)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _field(_serial, 'الرقم التسلسلي'),
                  const SizedBox(height: 10),
                  _field(_notes, 'ملاحظات الفني', maxLines: 2),
                  const SizedBox(height: 10),
                  _field(
                    _requiredParts,
                    'قطع مطلوبة، كل قطعة في سطر',
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(onPressed: _submit, child: const Text('تسجيل الاستلام')),
        ],
      ),
    );
  }
}

class _PartDialog extends StatefulWidget {
  const _PartDialog({
    required this.products,
    required this.currency,
    required this.existingIds,
  });

  final List<Product> products;
  final String currency;
  final Set<String> existingIds;

  @override
  State<_PartDialog> createState() => _PartDialogState();
}

class _PartDialogState extends State<_PartDialog> {
  final _quantity = TextEditingController(text: '1');
  final _price = TextEditingController();
  Product? _product;
  String? _error;

  @override
  void initState() {
    super.initState();
    final available = _available;
    if (available.isNotEmpty) {
      _product = available.first;
      _price.text = _major(_product!.sellingPrice);
    }
  }

  List<Product> get _available => widget.products
      .where((product) => !widget.existingIds.contains(product.id))
      .toList(growable: false);

  @override
  void dispose() {
    _quantity.dispose();
    _price.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final product = _product;
      if (product == null) {
        throw ArgumentError('اختر صنفاً.');
      }
      final quantity = Quantity.fromString(_quantity.text);
      if (quantity.milliUnits <= 0) {
        throw ArgumentError('الكمية يجب أن تكون أكبر من صفر.');
      }
      final part = RepairPart(
        id: 'part-${DateTime.now().microsecondsSinceEpoch}',
        productId: product.id,
        productName: product.name,
        quantity: quantity,
        unitPrice: Money(
          minorUnits: _minor(_price.text),
          currency: widget.currency,
        ),
        unitCost: product.purchasePrice,
      );
      Navigator.of(context).pop(part);
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('إضافة قطعة مستخدمة'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) _Banner(text: _error!),
              DropdownButtonFormField<Product>(
                value: _product,
                decoration: const InputDecoration(labelText: 'الصنف'),
                items: [
                  for (final product in _available)
                    DropdownMenuItem(value: product, child: Text(product.name)),
                ],
                onChanged: (product) {
                  if (product != null) {
                    setState(() {
                      _product = product;
                      _price.text = _major(product.sellingPrice);
                    });
                  }
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _quantity,
                decoration: const InputDecoration(labelText: 'الكمية'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _price,
                decoration: InputDecoration(
                  labelText: 'سعر البيع للوحدة (${widget.currency})',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(onPressed: _submit, child: const Text('إضافة')),
        ],
      ),
    );
  }
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({
    required this.storeId,
    required this.customerId,
    required this.repairId,
    required this.currency,
    required this.kind,
  });

  final String storeId;
  final String customerId;
  final String repairId;
  final String currency;
  final RepairPaymentKind kind;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _amount = TextEditingController();
  final _chequeNumber = TextEditingController();
  final _bankName = TextEditingController();
  PartyPaymentMethod _method = PartyPaymentMethod.cash;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _chequeNumber.dispose();
    _bankName.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final now = DateTime.now().toUtc();
      final id = 'repair-payment-${now.microsecondsSinceEpoch}';
      final payment = RepairPayment(
        id: id,
        storeId: widget.storeId,
        repairId: widget.repairId,
        customerId: widget.customerId,
        idempotencyKey: IdempotencyKey(id),
        postedAt: now,
        kind: widget.kind,
        paymentMethod: _method,
        amount: Money(
          minorUnits: _minor(_amount.text),
          currency: widget.currency,
        ),
        description: widget.kind.arabicLabel,
        chequeNumber:
            _method == PartyPaymentMethod.cheque ? _chequeNumber.text : null,
        bankName: _method == PartyPaymentMethod.cheque ? _bankName.text : null,
      );
      Navigator.of(context).pop(payment);
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final methods = PartyPaymentMethod.values
        .where(
          (value) =>
              widget.kind == RepairPaymentKind.settlement ||
              value != PartyPaymentMethod.cheque,
        )
        .toList(growable: false);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(widget.kind.arabicLabel),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) _Banner(text: _error!),
              TextField(
                controller: _amount,
                decoration: InputDecoration(
                  labelText: 'المبلغ (${widget.currency})',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<PartyPaymentMethod>(
                value: _method,
                decoration: const InputDecoration(labelText: 'طريقة الدفع'),
                items: [
                  for (final method in methods)
                    DropdownMenuItem(
                      value: method,
                      child: Text(_paymentLabel(method)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _method = value);
                  }
                },
              ),
              if (_method == PartyPaymentMethod.cheque) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _chequeNumber,
                  decoration: const InputDecoration(labelText: 'رقم الشيك'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _bankName,
                  decoration: const InputDecoration(labelText: 'البنك'),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(onPressed: _submit, child: const Text('ترحيل')),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Text(
        text,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }
}

Widget _field(
  TextEditingController controller,
  String label, {
  bool requiredField = false,
  int maxLines = 1,
  TextInputType? keyboardType,
  String? Function(String?)? validator,
}) {
  return TextFormField(
    controller: controller,
    maxLines: maxLines,
    keyboardType: keyboardType,
    decoration: InputDecoration(labelText: label),
    validator: validator ??
        (requiredField
            ? (value) => value == null || value.trim().isEmpty
                ? 'هذا الحقل مطلوب.'
                : null
            : null),
  );
}

String? _amountValidator(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  try {
    _minor(value);
    return null;
  } catch (_) {
    return 'أدخل مبلغاً صحيحاً.';
  }
}

int _minor(String value) {
  final normalized = value.trim().replaceAll(',', '');
  final match = RegExp(r'^\d+(?:\.\d{1,2})?$').firstMatch(normalized);
  if (match == null) {
    throw ArgumentError('المبلغ يجب أن يكون رقماً موجباً.');
  }
  final pieces = normalized.split('.');
  final major = int.parse(pieces.first);
  final minor = pieces.length == 1 ? 0 : int.parse(pieces[1].padRight(2, '0'));
  return major * 100 + minor;
}

String _major(Money money) => (money.minorUnits / 100).toStringAsFixed(2);

String _dateText(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}

String _paymentLabel(PartyPaymentMethod method) {
  switch (method) {
    case PartyPaymentMethod.cash:
      return 'نقدي';
    case PartyPaymentMethod.bank:
      return 'تحويل بنكي';
    case PartyPaymentMethod.card:
      return 'بطاقة';
    case PartyPaymentMethod.cheque:
      return 'شيك';
  }
}
