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
import '../domain/entities/sale.dart';
import '../domain/entities/sale_line.dart';
import '../domain/entities/sale_posting_plan.dart';
import '../domain/enums/sale_payment_method.dart';
import '../domain/repositories/sale_repository.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({
    required this.repository,
    required this.productRepository,
    required this.user,
    required this.membership,
    super.key,
  });

  final SaleRepository? repository;
  final ProductRepository? productRepository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  static const _cashAccountId = '1110';
  static const _bankAccountId = '1121';
  static const _cardAccountId = '1160';
  static const _customerReceivableAccountId = '1140';
  static const _inventoryAccountId = '1150';
  static const _salesAccountId = '4100';
  static const _costOfSalesAccountId = '5100';

  final _searchController = TextEditingController();
  final _customerController = TextEditingController();
  final Map<String, _SaleCartLine> _cart = <String, _SaleCartLine>{};

  List<Product> _products = const <Product>[];
  SalePaymentMethod _paymentMethod = SalePaymentMethod.cash;
  bool _isLoading = true;
  bool _isPosting = false;
  String? _errorMessage;

  String get _currency {
    if (_cart.isEmpty) {
      return 'ILS';
    }
    return _cart.values.first.product.sellingPrice.currency;
  }

  Money get _cartTotal {
    return _cart.values.fold(
      Money.zero(currency: _currency),
      (total, line) => total + line.subtotal,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  Widget build(BuildContext context) {
    final search = _searchController.text.trim().toLowerCase();
    final filteredProducts = _products
        .where(
          (product) =>
              search.isEmpty ||
              product.name.toLowerCase().contains(search) ||
              (product.sku?.toLowerCase().contains(search) ?? false) ||
              (product.barcode?.toLowerCase().contains(search) ?? false),
        )
        .toList(growable: false);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final products = _buildProductsPanel(filteredProducts);
          final cart = _buildCartPanel();

          if (constraints.maxWidth < 900) {
            return Column(
              children: [
                Expanded(child: products),
                SizedBox(height: 380, child: cart),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: products),
              SizedBox(width: 390, child: cart),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProductsPanel(List<Product> products) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_outlined),
                const SizedBox(width: 8),
                Text(
                  'الأصناف',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                Text('${products.length} صنف'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'ابحث بالاسم أو SKU أو الباركود',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(child: _buildProductList(products)),
        ],
      ),
    );
  }

  Widget _buildProductList(List<Product> products) {
    if (widget.productRepository == null) {
      return const Center(
        child: Text(
          'مستودع الأصناف غير موصول بهذه البيئة.',
          textAlign: TextAlign.center,
        ),
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
              onPressed: _loadProducts,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }
    if (products.isEmpty) {
      return const Center(child: Text('لا توجد أصناف مطابقة.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: products.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final product = products[index];
        final available = product.isService
            ? 'خدمة'
            : 'المتاح: ${product.quantityOnHand.formatted}';
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Icon(
                product.isService
                    ? Icons.design_services_outlined
                    : Icons.inventory_2_outlined,
              ),
            ),
            title: Text(product.name),
            subtitle: Text(
              '${product.sellingPrice.formatted} • $available',
            ),
            trailing: IconButton(
              tooltip: 'إضافة',
              onPressed: () => _addProduct(product),
              icon: const Icon(Icons.add_circle_outline),
            ),
            onTap: () => _addProduct(product),
          ),
        );
      },
    );
  }

  Widget _buildCartPanel() {
    return Card(
      margin: const EdgeInsets.fromLTRB(0, 12, 12, 12),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
            child: Row(
              children: [
                const Icon(Icons.shopping_cart_outlined),
                const SizedBox(width: 8),
                Text(
                  'الفاتورة الحالية',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                if (_cart.isNotEmpty)
                  IconButton(
                    tooltip: 'تفريغ الفاتورة',
                    onPressed: _clearCart,
                    icon: const Icon(Icons.delete_sweep_outlined),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _cart.isEmpty
                ? const Center(child: Text('أضف أصنافاً للبدء.'))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _cart.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = _cart.values.elementAt(index);
                      return _buildCartLine(item);
                    },
                  ),
          ),
          const Divider(height: 1),
          _buildPaymentControls(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isPosting ? null : _postSale,
                icon: _isPosting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  _isPosting
                      ? 'جارٍ الترحيل...'
                      : 'ترحيل البيع • ${_cartTotal.formatted}',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartLine(_SaleCartLine item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            item.product.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                item.subtotal.formatted,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => _decrementProduct(item.product),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text(item.quantity.formatted),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => _addProduct(item.product),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<SalePaymentMethod>(
            initialValue: _paymentMethod,
            decoration: const InputDecoration(
              labelText: 'طريقة الدفع',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
            items: SalePaymentMethod.values
                .map(
                  (method) => DropdownMenuItem<SalePaymentMethod>(
                    value: method,
                    child: Text(method.arabicLabel),
                  ),
                )
                .toList(growable: false),
            onChanged: _isPosting
                ? null
                : (method) {
                    if (method != null) {
                      setState(() => _paymentMethod = method);
                    }
                  },
          ),
          if (_paymentMethod == SalePaymentMethod.credit)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: _customerController,
                enabled: !_isPosting,
                decoration: const InputDecoration(
                  labelText: 'معرّف العميل',
                  hintText: 'أدخل customerId',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('الإجمالي'),
              const Spacer(),
              Text(
                _cartTotal.formatted,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _loadProducts() async {
    final repository = widget.productRepository;
    if (repository == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await repository.getProducts(
      context: StoreContext(
        storeId: widget.membership.storeId,
        userId: widget.user.id,
      ),
    );
    if (!mounted) {
      return;
    }

    if (result is FailureResult<List<Product>>) {
      setState(() {
        _isLoading = false;
        _errorMessage = result.failure.message;
      });
      return;
    }

    if (result is Success<List<Product>>) {
      setState(() {
        _isLoading = false;
        _products = result.value;
      });
    }
  }

  void _addProduct(Product product) {
    if (!product.isService) {
      final current =
          _cart[product.id]?.quantity ?? const Quantity.fromMilliUnits(0);
      final next = current + const Quantity.fromMilliUnits(1000);
      if (next.milliUnits > product.quantityOnHand.milliUnits) {
        _showMessage('الكمية المتاحة من ${product.name} لا تكفي.');
        return;
      }
    }

    final current = _cart[product.id];
    setState(() {
      _cart[product.id] = current == null
          ? _SaleCartLine(
              product: product,
              quantity: const Quantity.fromMilliUnits(1000),
            )
          : current.copyWith(
              quantity: current.quantity + const Quantity.fromMilliUnits(1000),
            );
    });
  }

  void _decrementProduct(Product product) {
    final current = _cart[product.id];
    if (current == null) {
      return;
    }

    if (current.quantity.milliUnits <= Quantity.scale) {
      setState(() => _cart.remove(product.id));
      return;
    }

    setState(() {
      _cart[product.id] = current.copyWith(
        quantity: current.quantity - const Quantity.fromMilliUnits(1000),
      );
    });
  }

  void _clearCart() {
    setState(() {
      _cart.clear();
      _customerController.clear();
      _paymentMethod = SalePaymentMethod.cash;
    });
  }

  Future<void> _postSale() async {
    final repository = widget.repository;
    if (repository == null) {
      _showMessage('مستودع المبيعات غير موصول بهذه البيئة.');
      return;
    }
    if (_cart.isEmpty) {
      _showMessage('أضف صنفاً واحداً على الأقل.');
      return;
    }

    final customerId = _customerController.text.trim();
    if (_paymentMethod == SalePaymentMethod.credit && customerId.isEmpty) {
      _showMessage('البيع الآجل يحتاج معرّف العميل.');
      return;
    }

    final saleId = 'sale-${DateTime.now().microsecondsSinceEpoch}';
    final sale = Sale(
      id: saleId,
      storeId: widget.membership.storeId,
      idempotencyKey: IdempotencyKey(saleId),
      postedAt: DateTime.now().toUtc(),
      paymentMethod: _paymentMethod,
      lines: _cart.values
          .map(
            (item) => SaleLine(
              id: '$saleId-${item.product.id}',
              productId: item.product.id,
              description: item.product.name,
              quantity: item.quantity,
              unitFactorToBase: const Quantity.fromMilliUnits(1000),
              unitPrice: item.product.sellingPrice,
              unitCost: item.product.purchasePrice,
              discount: Money.zero(
                currency: item.product.sellingPrice.currency,
              ),
              unitId: item.product.baseUnitId,
              unitName: item.product.baseUnitName,
              isService: item.product.isService,
            ),
          )
          .toList(growable: false),
      tax: Money.zero(currency: _currency),
      customerId:
          _paymentMethod == SalePaymentMethod.credit ? customerId : null,
      description: 'بيع من نقطة البيع',
    );

    setState(() => _isPosting = true);
    final result = await repository.postSale(
      context: sale.contextFor(widget.user.id),
      sale: sale,
      accounts: _postingAccounts,
    );
    if (!mounted) {
      return;
    }
    setState(() => _isPosting = false);

    if (result is FailureResult<SalePostingPlan>) {
      final failure = result.failure;
      if (failure is QueuedFailure) {
        _showMessage('تم حفظ البيع للطابور وسيُرحّل عند عودة الاتصال.');
      } else {
        _showMessage(failure.message);
      }
      return;
    }

    if (result is Success<SalePostingPlan>) {
      _clearCart();
      _showMessage('تم ترحيل البيع والقيد والمخزون بنجاح.');
    }
  }

  SalePostingAccounts get _postingAccounts {
    String? settlementAccountId;
    switch (_paymentMethod) {
      case SalePaymentMethod.cash:
        settlementAccountId = _cashAccountId;
      case SalePaymentMethod.bank:
        settlementAccountId = _bankAccountId;
      case SalePaymentMethod.card:
        settlementAccountId = _cardAccountId;
      case SalePaymentMethod.credit:
        settlementAccountId = null;
    }

    return SalePostingAccounts(
      settlementAccountId: settlementAccountId,
      customerReceivableAccountId: _customerReceivableAccountId,
      salesAccountId: _salesAccountId,
      inventoryAccountId: _inventoryAccountId,
      costOfSalesAccountId: _costOfSalesAccountId,
    );
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
    _customerController.dispose();
    super.dispose();
  }
}

class _SaleCartLine {
  const _SaleCartLine({
    required this.product,
    required this.quantity,
  });

  final Product product;
  final Quantity quantity;

  Money get subtotal {
    final numerator = product.sellingPrice.minorUnits * quantity.milliUnits;
    final minorUnits = (numerator + Quantity.scale ~/ 2) ~/ Quantity.scale;
    return Money(
      minorUnits: minorUnits,
      currency: product.sellingPrice.currency,
    );
  }

  _SaleCartLine copyWith({Quantity? quantity}) {
    return _SaleCartLine(
      product: product,
      quantity: quantity ?? this.quantity,
    );
  }
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
