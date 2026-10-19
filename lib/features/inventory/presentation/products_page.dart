import 'package:flutter/material.dart';

import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../domain/entities/product.dart';
import '../domain/repositories/product_repository.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({
    required this.repository,
    required this.user,
    required this.membership,
    super.key,
  });

  final ProductRepository? repository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final _searchController = TextEditingController();
  List<Product> _products = const [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  Widget build(BuildContext context) {
    final search = _searchController.text.trim().toLowerCase();
    final filtered = _products
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
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'ابحث بالاسم أو SKU أو الباركود',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(child: _buildBody(context, filtered)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<Product> products) {
    if (widget.repository == null) {
      return const Center(
        child: Text(
          'مستودع الأصناف غير موصول بهذه البيئة بعد.',
          textAlign: TextAlign.center,
        ),
      );
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return _ErrorState(
        message: _errorMessage!,
        onRetry: _loadProducts,
      );
    }
    if (products.isEmpty) {
      return const Center(child: Text('لا توجد أصناف مطابقة للبحث.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: products.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final product = products[index];
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
              [
                if (product.sku?.isNotEmpty == true) 'SKU: ${product.sku}',
                if (product.barcode?.isNotEmpty == true)
                  'باركود: ${product.barcode}',
                product.isService
                    ? 'خدمة'
                    : 'الرصيد: ${product.quantityOnHand.formatted}',
              ].join(' • '),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(product.sellingPrice.formatted),
                if (!product.isService && product.isLowStock)
                  Text(
                    'منخفض',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadProducts() async {
    final repository = widget.repository;
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }
}
