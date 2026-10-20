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
import '../domain/entities/purchase.dart';
import '../domain/entities/purchase_line.dart';
import '../domain/entities/purchase_posting_plan.dart';
import '../domain/enums/purchase_payment_method.dart';
import '../domain/repositories/purchase_repository.dart';

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({
    required this.repository,
    required this.productRepository,
    required this.user,
    required this.membership,
    super.key,
  });

  final PurchaseRepository? repository;
  final ProductRepository? productRepository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  static const _cashAccountId = '1110';
  static const _bankAccountId = '1121';
  static const _cardAccountId = '1160';
  static const _inventoryAccountId = '1150';
  static const _supplierPayableAccountId = '2110';
  static const _inputTaxAccountId = '1170';

  final _searchController = TextEditingController();
  final _supplierController = TextEditingController();
  final _taxController = TextEditingController();
  final Map<String, _PurchaseCartLine> _cart = <String, _PurchaseCartLine>{};

  List<Product> _products = const <Product>[];
  PurchasePaymentMethod _paymentMethod = PurchasePaymentMethod.cash;
  bool _isLoading = true;
  bool _isPosting = false;
  String? _errorMessage;

  String get _currency {
    if (_cart.isEmpty) {
      return 'ILS';
    }
    return _cart.values.first.product.purchasePrice.currency;
  }

  Money get _cartTotal {
    return _cart.values.fold(
      Money.zero(currency: _currency),
      (total, line) => total + line.subtotal,
    );
  }

  Money get _taxAmount {
    return _parseMoney(_taxController.text, currency: _currency) ??
        Money.zero(currency: _currency);
  }

  Money? _parseMoney(String raw, {required String currency}) {
    final normalized = raw.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      return Money.zero(currency: currency);
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
    return Money(minorUnits: major * 100 + fraction, currency: currency);
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
                Text('الأصناف', style: Theme.of(context).textTheme.titleLarge),
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
            subtitle: Text('${product.purchasePrice.formatted} • $available'),
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
                  'فاتورة الشراء',
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
                onPressed: _isPosting ? null : _postPurchase,
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
                      : 'ترحيل الشراء • ${(_cartTotal + _taxAmount).formatted}',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartLine(_PurchaseCartLine item) {
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
          DropdownButtonFormField<PurchasePaymentMethod>(
            initialValue: _paymentMethod,
            decoration: const InputDecoration(
              labelText: 'طريقة الدفع',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
            items: PurchasePaymentMethod.values
                .map(
                  (method) => DropdownMenuItem<PurchasePaymentMethod>(
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
          if (_paymentMethod == PurchasePaymentMethod.credit)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: _supplierController,
                enabled: !_isPosting,
                decoration: const InputDecoration(
                  labelText: 'معرّف المورد',
                  hintText: 'أدخل supplierId',
                  prefixIcon: Icon(Icons.local_shipping_outlined),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextField(
              controller: _taxController,
              enabled: !_isPosting,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'ضريبة المدخلات',
                hintText: '0.00',
                prefixIcon: Icon(Icons.percent_outlined),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('الإجمالي قبل الضريبة'),
              const Spacer(),
              Text(_cartTotal.formatted),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('الإجمالي'),
              const Spacer(),
              Text(
                (_cartTotal + _taxAmount).formatted,
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
    if (product.isService) {
      _showMessage('الخدمات لا تُستلم عبر فاتورة شراء.');
      return;
    }

    final current = _cart[product.id];
    setState(() {
      _cart[product.id] = current == null
          ? _PurchaseCartLine(
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
      _supplierController.clear();
      _taxController.clear();
      _paymentMethod = PurchasePaymentMethod.cash;
    });
  }

  Future<void> _postPurchase() async {
    final repository = widget.repository;
    if (repository == null) {
      _showMessage('مستودع المشتريات غير موصول بهذه البيئة.');
      return;
    }
    if (_cart.isEmpty) {
      _showMessage('أضف صنفاً واحداً على الأقل للشراء.');
      return;
    }

    final supplierId = _supplierController.text.trim();
    if (_paymentMethod == PurchasePaymentMethod.credit && supplierId.isEmpty) {
      _showMessage('الشراء الآجل يحتاج معرّف المورد.');
      return;
    }

    final tax = _parseMoney(_taxController.text, currency: _currency);
    if (tax == null) {
      _showMessage('قيمة الضريبة غير صحيحة.');
      return;
    }

    final purchaseId = 'purchase-${DateTime.now().microsecondsSinceEpoch}';
    final purchase = Purchase(
      id: purchaseId,
      storeId: widget.membership.storeId,
      idempotencyKey: IdempotencyKey(purchaseId),
      postedAt: DateTime.now().toUtc(),
      paymentMethod: _paymentMethod,
      lines: _cart.values
          .map(
            (item) => PurchaseLine(
              id: '$purchaseId-${item.product.id}',
              productId: item.product.id,
              description: item.product.name,
              quantity: item.quantity,
              unitFactorToBase: const Quantity.fromMilliUnits(1000),
              unitCost: item.product.purchasePrice,
              discount: Money.zero(
                currency: item.product.purchasePrice.currency,
              ),
              unitId: item.product.baseUnitId,
              unitName: item.product.baseUnitName,
            ),
          )
          .toList(growable: false),
      tax: tax,
      supplierId:
          _paymentMethod == PurchasePaymentMethod.credit ? supplierId : null,
      description: 'شراء من شاشة المشتريات',
    );

    setState(() => _isPosting = true);
    final result = await repository.postPurchase(
      context: purchase.contextFor(widget.user.id),
      purchase: purchase,
      accounts: _postingAccounts,
    );
    if (!mounted) {
      return;
    }
    setState(() => _isPosting = false);

    if (result is FailureResult<PurchasePostingPlan>) {
      final failure = result.failure;
      if (failure is QueuedFailure) {
        _showMessage('تم حفظ الشراء للطابور وسيُرحّل عند عودة الاتصال.');
      } else {
        _showMessage(failure.message);
      }
      return;
    }

    if (result is Success<PurchasePostingPlan>) {
      _clearCart();
      _showMessage('تم ترحيل الشراء والقيد والمخزون بنجاح.');
    }
  }

  PurchasePostingAccounts get _postingAccounts {
    String? settlementAccountId;
    switch (_paymentMethod) {
      case PurchasePaymentMethod.cash:
        settlementAccountId = _cashAccountId;
      case PurchasePaymentMethod.bank:
        settlementAccountId = _bankAccountId;
      case PurchasePaymentMethod.card:
        settlementAccountId = _cardAccountId;
      case PurchasePaymentMethod.credit:
        settlementAccountId = null;
    }

    return PurchasePostingAccounts(
      settlementAccountId: settlementAccountId,
      inventoryAccountId: _inventoryAccountId,
      supplierPayableAccountId: _supplierPayableAccountId,
      inputTaxAccountId: _inputTaxAccountId,
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
    _supplierController.dispose();
    _taxController.dispose();
    super.dispose();
  }
}

class _PurchaseCartLine {
  const _PurchaseCartLine({required this.product, required this.quantity});

  final Product product;
  final Quantity quantity;

  Money get subtotal {
    final numerator = product.purchasePrice.minorUnits * quantity.milliUnits;
    final minorUnits = (numerator + Quantity.scale ~/ 2) ~/ Quantity.scale;
    return Money(
      minorUnits: minorUnits,
      currency: product.purchasePrice.currency,
    );
  }

  _PurchaseCartLine copyWith({Quantity? quantity}) {
    return _PurchaseCartLine(
      product: product,
      quantity: quantity ?? this.quantity,
    );
  }
}

extension on PurchasePaymentMethod {
  String get arabicLabel {
    switch (this) {
      case PurchasePaymentMethod.cash:
        return 'نقدي';
      case PurchasePaymentMethod.bank:
        return 'بنك';
      case PurchasePaymentMethod.card:
        return 'بطاقة';
      case PurchasePaymentMethod.credit:
        return 'آجل';
    }
  }
}
