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
import '../../sales/domain/entities/sale_posting_plan.dart';
import '../../sales/domain/enums/sale_payment_method.dart';
import '../domain/entities/offer.dart';
import '../domain/entities/offer_line.dart';
import '../domain/entities/offer_order.dart';
import '../domain/entities/offer_order_confirmation.dart';
import '../domain/enums/offer_order_status.dart';
import '../domain/enums/offer_price_type.dart';
import '../domain/repositories/offer_repository.dart';

class OffersPage extends StatefulWidget {
  const OffersPage({
    required this.repository,
    required this.productRepository,
    required this.partyRepository,
    required this.user,
    required this.membership,
    super.key,
  });

  final OfferRepository? repository;
  final ProductRepository? productRepository;
  final PartyRepository? partyRepository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<OffersPage> createState() => _OffersPageState();
}

class _OffersPageState extends State<OffersPage> {
  static const _cashAccountId = '1110';
  static const _bankAccountId = '1121';
  static const _cardAccountId = '1160';
  static const _customerReceivableAccountId = '1140';
  static const _inventoryAccountId = '1150';
  static const _salesAccountId = '4100';
  static const _costOfSalesAccountId = '5100';

  final _searchController = TextEditingController();
  List<Offer> _offers = const <Offer>[];
  List<OfferOrder> _orders = const <OfferOrder>[];
  bool _showOrders = false;
  bool _isLoading = true;
  String? _errorMessage;

  StoreContext get _context => StoreContext(
        storeId: widget.membership.storeId,
        userId: widget.user.id,
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = widget.repository;
    if (repository == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'مستودع العروض غير موصول بهذه البيئة.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final offersResult = await repository.getOffers(context: _context);
    final ordersResult = await repository.getOfferOrders(context: _context);
    if (!mounted) {
      return;
    }

    String? error;
    if (offersResult is Success<List<Offer>>) {
      _offers = offersResult.value;
    } else if (offersResult is FailureResult<List<Offer>>) {
      error = offersResult.failure.message;
    }
    if (ordersResult is Success<List<OfferOrder>>) {
      _orders = ordersResult.value;
    } else if (ordersResult is FailureResult<List<OfferOrder>>) {
      error ??= ordersResult.failure.message;
    }
    setState(() {
      _isLoading = false;
      _errorMessage = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final search = _searchController.text.trim().toLowerCase();
    final offers = _offers
        .where(
          (offer) =>
              search.isEmpty ||
              offer.name.toLowerCase().contains(search) ||
              offer.offerNumber.toLowerCase().contains(search),
        )
        .toList(growable: false);
    final orders = _orders
        .where(
          (order) =>
              search.isEmpty ||
              order.orderNumber.toLowerCase().contains(search) ||
              order.offerNumber.toLowerCase().contains(search) ||
              order.customerName.toLowerCase().contains(search),
        )
        .toList(growable: false);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Icon(Icons.request_quote_outlined),
                Text(
                  'العروض والطلبات',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                FilledButton.icon(
                  onPressed: _isLoading ? null : _showCreateOffer,
                  icon: const Icon(Icons.add),
                  label: const Text('عرض جديد'),
                ),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _showCreateOrder,
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('طلب من عرض'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'ابحث بالاسم أو الرقم أو العميل',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                ChoiceChip(
                  selected: !_showOrders,
                  label: const Text('العروض'),
                  onSelected: (_) => setState(() => _showOrders = false),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  selected: _showOrders,
                  label: const Text('الطلبات'),
                  onSelected: (_) => setState(() => _showOrders = true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? _buildError()
                    : _showOrders
                        ? _buildOrders(orders)
                        : _buildOffers(offers),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 44),
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

  Widget _buildOffers(List<Offer> offers) {
    if (offers.isEmpty) {
      return const Center(child: Text('لا توجد عروض.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: offers.length,
        itemBuilder: (context, index) => _buildOfferCard(offers[index]),
      ),
    );
  }

  Widget _buildOfferCard(Offer offer) {
    final status = offer.isCurrentlyActive ? 'نشط' : 'غير نشط';
    final statusColor =
        offer.isCurrentlyActive ? Colors.green : Colors.grey;
    return Card(
      child: ExpansionTile(
        leading: CircleAvatar(
          child: Icon(
            offer.isCurrentlyActive
                ? Icons.local_offer_outlined
                : Icons.archive_outlined,
          ),
        ),
        title: Text(offer.name),
        subtitle: Text(
          offer.offerNumber +
              ' • ' +
              offer.lines.length.toString() +
              ' أصناف • ' +
              offer.totalFinal.formatted,
        ),
        trailing: Chip(
          label: Text(status),
          labelStyle: TextStyle(color: statusColor),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (offer.description?.trim().isNotEmpty == true)
                  Text(offer.description!),
                const SizedBox(height: 8),
                Text(
                  'الإجمالي قبل الخصم: ' +
                      offer.originalTotal.formatted +
                      ' | الخصم: ' +
                      offer.totalDiscount.formatted +
                      ' | النهائي: ' +
                      offer.totalFinal.formatted,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _setOfferActive(offer),
                      icon: Icon(
                        offer.isActive
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      label: Text(offer.isActive ? 'تعطيل' : 'تفعيل'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _archiveOffer(offer),
                      icon: const Icon(Icons.archive_outlined),
                      label: const Text('أرشفة'),
                    ),
                    FilledButton.icon(
                      onPressed: offer.isCurrentlyActive
                          ? () => _showCreateOrder(initialOffer: offer)
                          : null,
                      icon: const Icon(Icons.add_shopping_cart_outlined),
                      label: const Text('إنشاء طلب'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrders(List<OfferOrder> orders) {
    if (orders.isEmpty) {
      return const Center(child: Text('لا توجد طلبات عروض.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: orders.length,
        itemBuilder: (context, index) => _buildOrderCard(orders[index]),
      ),
    );
  }

  Widget _buildOrderCard(OfferOrder order) {
    final color = switch (order.status) {
      OfferOrderStatus.pending => Colors.orange,
      OfferOrderStatus.confirmed => Colors.green,
      OfferOrderStatus.cancelled => Colors.red,
    };
    return Card(
      child: ListTile(
        leading: Icon(Icons.receipt_long_outlined, color: color),
        title: Text(order.orderNumber + ' • ' + order.customerName),
        subtitle: Text(
          order.offerNumber +
              ' • ' +
              order.total.formatted +
              ' • ' +
              order.status.arabicLabel,
        ),
        isThreeLine: true,
        trailing: order.status == OfferOrderStatus.pending
            ? Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: 'تأكيد وترحيل',
                    onPressed: () => _confirmOrder(order),
                    icon: const Icon(Icons.check_circle_outline),
                  ),
                  IconButton(
                    tooltip: 'إلغاء',
                    onPressed: () => _cancelOrder(order),
                    icon: const Icon(Icons.cancel_outlined),
                  ),
                ],
              )
            : Chip(label: Text(order.status.arabicLabel)),
      ),
    );
  }

  Future<void> _showCreateOffer() async {
    final productRepository = widget.productRepository;
    final repository = widget.repository;
    if (productRepository == null || repository == null) {
      _showMessage('مستودع الأصناف أو العروض غير موصول.');
      return;
    }
    final result = await productRepository.getProducts(context: _context);
    if (!mounted) {
      return;
    }
    if (result is FailureResult<List<Product>>) {
      _showMessage(result.failure.message);
      return;
    }
    final products = (result as Success<List<Product>>).value;
    final offer = await showDialog<Offer>(
      context: context,
      builder: (_) => _CreateOfferDialog(products: products),
    );
    if (offer == null || !mounted) {
      return;
    }
    final saveResult =
        await repository.createOffer(
      context: _context,
      offer: offer.copyWith(storeId: _context.storeId),
    );
    if (!mounted) {
      return;
    }
    _showResultMessage(saveResult, 'تم حفظ العرض.');
    if (saveResult is Success<Offer>) {
      await _load();
    }
  }

  Future<void> _showCreateOrder({Offer? initialOffer}) async {
    final repository = widget.repository;
    final partyRepository = widget.partyRepository;
    if (repository == null || partyRepository == null) {
      _showMessage('مستودع العروض أو العملاء غير موصول.');
      return;
    }
    final parties = await partyRepository.getParties(
      context: _context,
      type: PartyType.customer,
    );
    if (!mounted) {
      return;
    }
    if (parties is FailureResult<List<Party>>) {
      _showMessage(parties.failure.message);
      return;
    }
    final customers = (parties as Success<List<Party>>).value;
    final activeOffers =
        _offers.where((offer) => offer.isCurrentlyActive).toList();
    if (activeOffers.isEmpty || customers.isEmpty) {
      _showMessage('يلزم وجود عرض نشط وعميل واحد على الأقل.');
      return;
    }
    final order = await showDialog<OfferOrder>(
      context: context,
      builder: (_) => _CreateOfferOrderDialog(
        offers: activeOffers,
        customers: customers,
        initialOffer: initialOffer,
        storeId: _context.storeId,
      ),
    );
    if (order == null || !mounted) {
      return;
    }
    final saveResult =
        await repository.createOfferOrder(context: _context, order: order);
    if (!mounted) {
      return;
    }
    _showResultMessage(saveResult, 'تم إنشاء الطلب بحالة قيد الانتظار.');
    if (saveResult is Success<OfferOrder>) {
      await _load();
    }
  }

  Future<void> _setOfferActive(Offer offer) async {
    final repository = widget.repository;
    if (repository == null) {
      return;
    }
    final result = await repository.setOfferActive(
      context: _context,
      offerId: offer.id,
      isActive: !offer.isActive,
    );
    if (!mounted) {
      return;
    }
    _showResultMessage(result, 'تم تحديث حالة العرض.');
    if (result is Success<void>) {
      await _load();
    }
  }

  Future<void> _archiveOffer(Offer offer) async {
    final repository = widget.repository;
    if (repository == null) {
      return;
    }
    final result = await repository.archiveOffer(
      context: _context,
      offerId: offer.id,
    );
    if (!mounted) {
      return;
    }
    _showResultMessage(result, 'تمت أرشفة العرض.');
    if (result is Success<void>) {
      await _load();
    }
  }

  Future<void> _cancelOrder(OfferOrder order) async {
    final repository = widget.repository;
    if (repository == null) {
      return;
    }
    final result = await repository.cancelOfferOrder(
      context: _context,
      orderId: order.id,
    );
    if (!mounted) {
      return;
    }
    _showResultMessage(result, 'تم إلغاء الطلب.');
    if (result is Success<void>) {
      await _load();
    }
  }

  Future<void> _confirmOrder(OfferOrder order) async {
    final repository = widget.repository;
    if (repository == null) {
      return;
    }
    final paymentMethod = await showDialog<SalePaymentMethod>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('طريقة التحصيل'),
        children: [
          for (final method in SalePaymentMethod.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, method),
              child: Text(method.arabicLabel),
            ),
        ],
      ),
    );
    if (paymentMethod == null || !mounted) {
      return;
    }
    final accounts = SalePostingAccounts(
      settlementAccountId: switch (paymentMethod) {
        SalePaymentMethod.cash => _cashAccountId,
        SalePaymentMethod.bank => _bankAccountId,
        SalePaymentMethod.card => _cardAccountId,
        SalePaymentMethod.credit => null,
      },
      customerReceivableAccountId: _customerReceivableAccountId,
      salesAccountId: _salesAccountId,
      inventoryAccountId: _inventoryAccountId,
      costOfSalesAccountId: _costOfSalesAccountId,
    );
    final result = await repository.confirmOfferOrder(
      context: _context,
      order: order,
      paymentMethod: paymentMethod,
      accounts: accounts,
    );
    if (!mounted) {
      return;
    }
    _showResultMessage(result, 'تم تأكيد الطلب وترحيل البيع والقيد.');
    if (result is Success<OfferOrderConfirmation>) {
      await _load();
    }
  }

  void _showResultMessage<T>(Result<T> result, String successMessage) {
    if (result is Success<T>) {
      _showMessage(successMessage);
    } else if (result is FailureResult<T>) {
      _showMessage(result.failure.message);
    }
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
    _searchController.dispose();
    super.dispose();
  }
}

class _CreateOfferDialog extends StatefulWidget {
  const _CreateOfferDialog({required this.products});

  final List<Product> products;

  @override
  State<_CreateOfferDialog> createState() => _CreateOfferDialogState();
}

class _CreateOfferDialogState extends State<_CreateOfferDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _globalDiscountController = TextEditingController();
  final Map<String, _OfferDraft> _selected = <String, _OfferDraft>{};
  DateTime? _startDate;
  DateTime? _endDate;
  String? _errorMessage;

  String get _currency => widget.products.isEmpty
      ? 'ILS'
      : widget.products.first.sellingPrice.currency;

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );
    if (range != null) {
      setState(() {
        _startDate = range.start.toUtc();
        _endDate = range.end
            .add(const Duration(days: 1))
            .subtract(const Duration(milliseconds: 1))
            .toUtc();
      });
    }
  }

  void _toggleProduct(Product product, bool selected) {
    setState(() {
      if (selected) {
        final original = product.sellingPrice;
        final proposed = product.isService
            ? product.sellingPrice
            : Money(
                minorUnits: product.wholesalePrice.minorUnits >
                        original.minorUnits
                    ? original.minorUnits
                    : product.wholesalePrice.minorUnits,
                currency: original.currency,
              );
        _selected[product.id] = _OfferDraft(
          product: product,
          finalPrice: proposed,
          priceType: product.isService
              ? OfferPriceType.retail
              : OfferPriceType.wholesale,
        );
      } else {
        _selected.remove(product.id)?.dispose();
      }
    });
  }

  Future<void> _save() async {
    try {
      final name = _nameController.text.trim();
      if (name.isEmpty) {
        throw ArgumentError('اسم العرض مطلوب.');
      }
      if (_selected.isEmpty) {
        throw ArgumentError('اختر صنفاً واحداً على الأقل.');
      }
      final lines = <OfferLine>[];
      for (final draft in _selected.values) {
        final price = _parseMoney(draft.priceController.text, _currency);
        if (price == null) {
          throw ArgumentError('تحقق من أسعار العرض.');
        }
        final quantity =
            Quantity.fromString(draft.quantityController.text.replaceAll(',', '.'));
        lines.add(
          OfferLine(
            id: 'offer-line-' + draft.product.id,
            productId: draft.product.id,
            productName: draft.product.name,
            originalUnitPrice: draft.product.sellingPrice,
            finalUnitPrice: price,
            quantity: quantity,
            unitFactorToBase: const Quantity.fromMilliUnits(1000),
            priceType: draft.priceType,
            unitId: null,
            unitName: draft.product.baseUnitName,
            isService: draft.product.isService,
          ),
        );
      }
      final discount =
          _parseMoney(_globalDiscountController.text, _currency) ??
              Money.zero(currency: _currency);
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final offer = Offer(
        id: 'offer-' + stamp.toString(),
        storeId: '',
        offerNumber: 'OFFER-' + stamp.toString(),
        name: name,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        lines: lines,
        createdAt: DateTime.now().toUtc(),
        isActive: true,
        globalDiscount: discount,
        startDate: _startDate,
        endDate: _endDate,
      );
      if (mounted) {
        Navigator.pop(context, offer);
      }
    } catch (error) {
      setState(() => _errorMessage = error.toString().replaceFirst('Invalid argument(s): ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('عرض جديد'),
      content: SizedBox(
        width: 700,
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'اسم العرض'),
              ),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'الوصف'),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: _pickDateRange,
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    _startDate == null
                        ? 'تحديد فترة العرض (اختياري)'
                        : 'الفترة محددة',
                  ),
                ),
              ),
              TextField(
                controller: _globalDiscountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'خصم إضافي على كامل العرض',
                ),
              ),
              const Divider(height: 24),
              for (final product in widget.products)
                CheckboxListTile(
                  value: _selected.containsKey(product.id),
                  onChanged: (value) => _toggleProduct(product, value == true),
                  title: Text(product.name),
                  subtitle: Text(
                    'بيع: ' +
                        product.sellingPrice.formatted +
                        ' • جملة: ' +
                        product.wholesalePrice.formatted,
                  ),
                ),
              if (_selected.isNotEmpty) ...[
                const Divider(height: 24),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    'تفاصيل الأصناف المختارة',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                for (final draft in _selected.values)
                  _OfferDraftEditor(
                    draft: draft,
                    currency: _currency,
                    onChanged: () => setState(() {}),
                  ),
              ],
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('حفظ'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _globalDiscountController.dispose();
    for (final draft in _selected.values) {
      draft.dispose();
    }
    super.dispose();
  }
}

class _OfferDraft {
  _OfferDraft({
    required this.product,
    required Money finalPrice,
    required this.priceType,
  }) : priceController = TextEditingController(
          text: (finalPrice.minorUnits / 100).toStringAsFixed(2),
        ),
        quantityController = TextEditingController(text: '1');

  final Product product;
  final TextEditingController priceController;
  final TextEditingController quantityController;
  OfferPriceType priceType;

  void dispose() {
    priceController.dispose();
    quantityController.dispose();
  }
}

class _OfferDraftEditor extends StatelessWidget {
  const _OfferDraftEditor({
    required this.draft,
    required this.currency,
    required this.onChanged,
  });

  final _OfferDraft draft;
  final String currency;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(child: Text(draft.product.name)),
            SizedBox(
              width: 100,
              child: TextField(
                controller: draft.quantityController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'الكمية'),
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 130,
              child: TextField(
                controller: draft.priceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'السعر ' + currency),
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<OfferPriceType>(
              value: draft.priceType,
              onChanged: (value) {
                if (value != null) {
                  draft.priceType = value;
                  onChanged();
                }
              },
              items: [
                for (final type in OfferPriceType.values)
                  DropdownMenuItem(
                    value: type,
                    child: Text(type.arabicLabel),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateOfferOrderDialog extends StatefulWidget {
  const _CreateOfferOrderDialog({
    required this.offers,
    required this.customers,
    required this.storeId,
    this.initialOffer,
  });

  final List<Offer> offers;
  final List<Party> customers;
  final String storeId;
  final Offer? initialOffer;

  @override
  State<_CreateOfferOrderDialog> createState() =>
      _CreateOfferOrderDialogState();
}

class _CreateOfferOrderDialogState extends State<_CreateOfferOrderDialog> {
  late Offer _offer;
  Party? _customer;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _offer = widget.initialOffer ?? widget.offers.first;
    _customer = widget.customers.first;
  }

  void _save() {
    final customer = _customer;
    if (customer == null) {
      setState(() => _errorMessage = 'اختر العميل.');
      return;
    }
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final order = OfferOrder(
      id: 'offer-order-' + stamp.toString(),
      storeId: widget.storeId,
      orderNumber: 'OO-' + stamp.toString(),
      offerId: _offer.id,
      offerNumber: _offer.offerNumber,
      customerId: customer.id,
      customerName: customer.name,
      lines: _offer.lines,
      createdAt: DateTime.now().toUtc(),
      globalDiscount: _offer.globalDiscount,
      status: OfferOrderStatus.pending,
    );
    Navigator.pop(context, order);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إنشاء طلب من عرض'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<Offer>(
            value: _offer,
            decoration: const InputDecoration(labelText: 'العرض'),
            items: [
              for (final offer in widget.offers)
                DropdownMenuItem(
                  value: offer,
                  child: Text(offer.name + ' • ' + offer.totalFinal.formatted),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _offer = value);
              }
            },
          ),
          DropdownButtonFormField<Party>(
            value: _customer,
            decoration: const InputDecoration(labelText: 'العميل'),
            items: [
              for (final customer in widget.customers)
                DropdownMenuItem(
                  value: customer,
                  child: Text(customer.name),
                ),
            ],
            onChanged: (value) => setState(() => _customer = value),
          ),
          const SizedBox(height: 8),
          Text('الإجمالي: ' + _offer.totalFinal.formatted),
          if (_errorMessage != null)
            Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('إنشاء'),
        ),
      ],
    );
  }
}

Money? _parseMoney(String raw, String currency) {
  final normalized = raw.trim().replaceAll(',', '.');
  if (normalized.isEmpty) {
    return Money.zero(currency: currency);
  }
  final parts = normalized.split('.');
  if (parts.length > 2 || parts.first.isEmpty) {
    return null;
  }
  final major = int.tryParse(parts.first);
  if (major == null || major < 0) {
    return null;
  }
  final fractionText = parts.length == 1 ? '' : parts[1];
  if (fractionText.length > 2 ||
      (fractionText.isNotEmpty && int.tryParse(fractionText) == null)) {
    return null;
  }
  final fraction = fractionText.isEmpty
      ? 0
      : int.parse(fractionText.padRight(2, '0'));
  return Money(
    minorUnits: major * 100 + fraction,
    currency: currency,
  );
}

extension on SalePaymentMethod {
  String get arabicLabel {
    switch (this) {
      case SalePaymentMethod.cash:
        return 'نقدي';
      case SalePaymentMethod.bank:
        return 'بنك';
      case SalePaymentMethod.card:
        return 'بطاقة';
      case SalePaymentMethod.credit:
        return 'آجل';
    }
  }
}
