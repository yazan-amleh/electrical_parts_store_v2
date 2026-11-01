import 'package:flutter/material.dart';

import '../../../core/result/result.dart';
import '../../../core/money/money.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../../auth/domain/enums/store_role.dart';
import '../../categories/domain/entities/category.dart';
import '../../categories/domain/repositories/category_repository.dart';
import '../domain/entities/product.dart';
import '../domain/repositories/product_repository.dart';
import '../domain/repositories/inventory_repository.dart';
import 'product_details_page.dart';
import 'product_editor_dialog.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({
    required this.repository,
    required this.user,
    required this.membership,
    this.categoryRepository,
    this.inventoryRepository,
    super.key,
  });

  final ProductRepository? repository;
  final AuthenticatedUser user;
  final StoreMembership membership;
  final CategoryRepository? categoryRepository;
  final InventoryRepository? inventoryRepository;

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final _searchController = TextEditingController();
  List<Product> _products = const [];
  List<Category> _categories = const <Category>[];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _showInactive = false;
  bool _lowStockOnly = false;
  String _productType = 'all';
  String? _selectedCategoryId;
  String? _errorMessage;
  String _sortOrder = 'name';
  int _visibleLimit = 50;
  int _loadEpoch = 0;
  int _categoryEpoch = 0;
  static const _pageSize = 50;

  bool get _canManage => widget.membership.role.canManageInventory;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _loadCategories();
  }

  @override
  void didUpdateWidget(covariant ProductsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.id != widget.user.id ||
        oldWidget.membership.storeId != widget.membership.storeId ||
        oldWidget.repository != widget.repository ||
        oldWidget.categoryRepository != widget.categoryRepository) {
      ++_loadEpoch;
      ++_categoryEpoch;
      _products = const <Product>[];
      _categories = const <Category>[];
      _selectedCategoryId = null;
      _showInactive = false;
      _lowStockOnly = false;
      _productType = 'all';
      _sortOrder = 'name';
      _visibleLimit = _pageSize;
      _searchController.clear();
      _errorMessage = null;
      _loadProducts();
      _loadCategories();
    }
  }

  StoreContext get _storeContext => StoreContext(
        storeId: widget.membership.storeId,
        userId: widget.user.id,
      );

  @override
  Widget build(BuildContext context) {
    final search = _searchController.text.trim().toLowerCase();
    final filtered = _products.where((product) {
      if (!_showInactive && !product.isActive) return false;
      if (_lowStockOnly && !product.isLowStock) return false;
      if (_productType == 'service' && !product.isService) return false;
      if (_productType == 'stock' && product.isService) return false;
      if (_selectedCategoryId != null &&
          product.categoryId != _selectedCategoryId) {
        return false;
      }
      return search.isEmpty ||
          product.name.toLowerCase().contains(search) ||
          (product.sku?.toLowerCase().contains(search) ?? false) ||
          (product.barcode?.toLowerCase().contains(search) ?? false);
    }).toList();
    filtered.sort((left, right) {
      int compare = 0;
      if (_sortOrder == 'stock-ascending' || _sortOrder == 'stock-descending') {
        if (left.isService != right.isService) {
          return left.isService ? 1 : -1;
        }
        compare = left.quantityOnHand.milliUnits
            .compareTo(right.quantityOnHand.milliUnits);
        if (_sortOrder == 'stock-descending') compare = -compare;
      } else if (_sortOrder == 'price') {
        compare =
            left.sellingPrice.currency.compareTo(right.sellingPrice.currency);
        if (compare == 0) {
          compare = left.sellingPrice.minorUnits
              .compareTo(right.sellingPrice.minorUnits);
        }
      } else if (_sortOrder == 'sku') {
        compare = (left.sku ?? '').compareTo(right.sku ?? '');
      }
      if (compare != 0) return compare;
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'ابحث بالاسم أو SKU أو الباركود',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => setState(() => _visibleLimit = _pageSize),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed:
                      widget.repository == null || !_canManage || _isSaving
                          ? null
                          : () => _openEditor(),
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة صنف'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final option in const [
                  ('all', 'الكل'),
                  ('stock', 'أصناف مخزنية'),
                  ('service', 'خدمات'),
                ])
                  ChoiceChip(
                    label: Text(option.$2),
                    selected: _productType == option.$1,
                    onSelected: (_) => setState(() {
                      _productType = option.$1;
                      _visibleLimit = _pageSize;
                    }),
                  ),
                FilterChip(
                  label: const Text('منخفض المخزون'),
                  selected: _lowStockOnly,
                  onSelected: (value) => setState(() {
                    _lowStockOnly = value;
                    _visibleLimit = _pageSize;
                  }),
                ),
                FilterChip(
                  label: const Text('إظهار غير النشط'),
                  selected: _showInactive,
                  onSelected: (value) => setState(() {
                    _showInactive = value;
                    _visibleLimit = _pageSize;
                  }),
                ),
                if (_categories.isNotEmpty)
                  DropdownButton<String?>(
                    value: _selectedCategoryId,
                    hint: const Text('كل التصنيفات'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('كل التصنيفات'),
                      ),
                      for (final category in _categories)
                        DropdownMenuItem<String?>(
                          value: category.id,
                          child: Text(category.name),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _selectedCategoryId = value;
                      _visibleLimit = _pageSize;
                    }),
                  ),
                DropdownButton<String>(
                  key: const ValueKey('products-sort'),
                  value: _sortOrder,
                  items: const [
                    DropdownMenuItem(
                        value: 'name', child: Text('ترتيب: الاسم')),
                    DropdownMenuItem(value: 'sku', child: Text('ترتيب: SKU')),
                    DropdownMenuItem(
                      value: 'stock-ascending',
                      child: Text('الأقل مخزونًا'),
                    ),
                    DropdownMenuItem(
                      value: 'stock-descending',
                      child: Text('الأكثر مخزونًا'),
                    ),
                    DropdownMenuItem(value: 'price', child: Text('سعر البيع')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _sortOrder = value;
                      _visibleLimit = _pageSize;
                    });
                  },
                ),
              ],
            ),
          ),
          _buildInventorySummary(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'مطابق للفلاتر: ${filtered.length} • المعروض: '
                    '${filtered.length < _visibleLimit ? filtered.length : _visibleLimit} '
                    'من أصل ${_products.length} صنف محمّل',
                  ),
                ),
                IconButton(
                  tooltip: 'تحديث الأصناف والتصنيفات',
                  onPressed: _isLoading ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(context, filtered)),
        ],
      ),
    );
  }

  Widget _buildInventorySummary(BuildContext context) {
    if (_isLoading || _errorMessage != null || widget.repository == null) {
      return const SizedBox.shrink();
    }
    final active = _products.where((p) => p.isActive).toList();
    final stock = active.where((p) => !p.isService);
    final low = stock.where((p) => p.isLowStock).length;
    final services = active.where((p) => p.isService).length;
    final valueByCurrency = <String, int>{};
    for (final product in stock) {
      final currency = product.inventoryValue.currency;
      valueByCurrency.update(
        currency,
        (value) => value + product.inventoryValue.minorUnits,
        ifAbsent: () => product.inventoryValue.minorUnits,
      );
    }
    final values = valueByCurrency.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Chip(label: Text('أصناف نشطة: ${active.length}')),
          Chip(label: Text('خدمات: $services')),
          Chip(label: Text('أصناف منخفضة: $low')),
          for (final entry in values)
            Chip(
              label: Text(
                'قيمة المخزون المحمّل — ${entry.key}: '
                '${Money(minorUnits: entry.value, currency: entry.key).formatted}',
              ),
            ),
          if (values.isNotEmpty)
            const Text(
              'قيمة الأصناف من حقل المخزون المحمّل، وليست رصيد حساب '
              'المخزون في دفتر الأستاذ.',
            ),
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
      return _ErrorState(message: _errorMessage!, onRetry: _loadProducts);
    }
    if (products.isEmpty) {
      return const Center(child: Text('لا توجد أصناف مطابقة للبحث.'));
    }

    final shown = products.take(_visibleLimit).toList(growable: false);
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: shown.length + (products.length > shown.length ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index >= shown.length) {
          return Center(
            child: OutlinedButton.icon(
              key: const ValueKey('products-show-more'),
              onPressed: () => setState(() => _visibleLimit += _pageSize),
              icon: const Icon(Icons.expand_more),
              label: Text(
                'عرض 50 صنفًا إضافيًا (${shown.length} من ${products.length})',
              ),
            ),
          );
        }
        final product = shown[index];
        return Card(
          child: ListTile(
            onTap: _isSaving ? null : () => _openDetails(product),
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
                if (!product.isActive) 'غير نشط',
              ].join(' • '),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
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
                if (_canManage)
                  IconButton(
                    tooltip: 'تعديل الصنف',
                    onPressed: _isSaving ? null : () => _openEditor(product),
                    icon: const Icon(Icons.edit_outlined),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openDetails(Product product) async {
    final repository = widget.repository;
    if (repository == null || product.storeId != widget.membership.storeId) {
      _showMessage('تعذر فتح تفاصيل هذا الصنف ضمن المتجر الحالي.');
      return;
    }
    final requestedContext = _storeContext;
    final epoch = _loadEpoch;
    final editRequested = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (detailsContext) => ProductDetailsPage(
          productId: product.id,
          contextScope: requestedContext,
          productRepository: repository,
          inventoryRepository: widget.inventoryRepository,
          onEdit:
              !_canManage ? null : () => Navigator.of(detailsContext).pop(true),
        ),
      ),
    );
    if (mounted &&
        epoch == _loadEpoch &&
        requestedContext.storeId == widget.membership.storeId &&
        requestedContext.userId == widget.user.id) {
      if (editRequested == true && _canManage) {
        await _openEditor(product);
      } else {
        await _loadProducts();
      }
    }
  }

  Future<void> _loadProducts() async {
    final repository = widget.repository;
    final contextAtStart = _storeContext;
    final epoch = ++_loadEpoch;
    bool stillCurrent() =>
        mounted &&
        epoch == _loadEpoch &&
        contextAtStart.storeId == widget.membership.storeId &&
        contextAtStart.userId == widget.user.id &&
        repository == widget.repository;

    if (repository == null) {
      setState(() {
        _isLoading = false;
        _products = const <Product>[];
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _products = const <Product>[];
    });

    final result = await repository.getProducts(
      context: contextAtStart,
      includeInactive: true,
    );
    if (!stillCurrent()) return;

    if (result is FailureResult<List<Product>>) {
      setState(() {
        _isLoading = false;
        _errorMessage = result.failure.message;
      });
      return;
    }

    if (result is Success<List<Product>>) {
      // Recheck document store IDs even when the repository has already
      // enforced its own tenant query.
      if (result.value.any((item) => item.storeId != contextAtStart.storeId)) {
        setState(() {
          _isLoading = false;
          _products = const <Product>[];
          _errorMessage = 'بيانات أصناف لا تتبع المتجر الحالي؛ تم رفض تحميلها.';
        });
        return;
      }
      setState(() {
        _isLoading = false;
        _products = result.value;
      });
    }
  }

  Future<void> _refresh() async {
    await Future.wait([_loadProducts(), _loadCategories()]);
  }

  Future<void> _openEditor([Product? initialProduct]) async {
    final repository = widget.repository;
    if (repository == null || !_canManage || _isSaving) {
      _showMessage('تعديل الأصناف غير متاح بصلاحياتك الحالية.');
      return;
    }

    final editContext = _storeContext;
    final editEpoch = _loadEpoch;
    final product = await showDialog<Product>(
      context: context,
      builder: (_) => ProductEditorDialog(
        storeId: widget.membership.storeId,
        initialProduct: initialProduct,
        categories: _categories,
      ),
    );
    if (!mounted ||
        product == null ||
        editEpoch != _loadEpoch ||
        editContext.storeId != widget.membership.storeId ||
        editContext.userId != widget.user.id ||
        product.storeId != editContext.storeId ||
        repository != widget.repository) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      final result = await repository.saveProduct(
        context: editContext,
        product: product,
      );
      if (!mounted ||
          editEpoch != _loadEpoch ||
          editContext.storeId != widget.membership.storeId ||
          editContext.userId != widget.user.id) {
        return;
      }

      if (result is FailureResult<void>) {
        _showMessage(result.failure.message);
        return;
      }
      if (result is Success<void>) {
        await _loadProducts();
        if (mounted) {
          _showMessage(
            initialProduct == null ? 'تمت إضافة الصنف.' : 'تم تحديث الصنف.',
          );
        }
      }
    } catch (error) {
      if (mounted) _showMessage('تعذر حفظ الصنف: $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _loadCategories() async {
    final repository = widget.categoryRepository;
    final requestedContext = _storeContext;
    final epoch = ++_categoryEpoch;
    if (repository == null) {
      if (mounted) setState(() => _categories = const <Category>[]);
      return;
    }

    final result = await repository.getCategories(context: requestedContext);
    if (!mounted ||
        epoch != _categoryEpoch ||
        repository != widget.categoryRepository ||
        requestedContext.storeId != widget.membership.storeId ||
        requestedContext.userId != widget.user.id) {
      return;
    }

    if (result is Success<List<Category>>) {
      if (result.value
          .any((category) => category.storeId != requestedContext.storeId)) {
        setState(() {
          _categories = const <Category>[];
          _selectedCategoryId = null;
        });
        return;
      }
      setState(() {
        _categories = result.value;
        if (_selectedCategoryId != null &&
            !_categories.any((c) => c.id == _selectedCategoryId)) {
          _selectedCategoryId = null;
        }
      });
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    ++_loadEpoch;
    ++_categoryEpoch;
    _searchController.dispose();
    super.dispose();
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

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
