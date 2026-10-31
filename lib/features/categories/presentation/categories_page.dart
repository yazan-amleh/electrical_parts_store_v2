import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../inventory/domain/entities/product.dart';
import '../../inventory/domain/repositories/product_repository.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../../auth/domain/enums/store_role.dart';
import '../domain/entities/category.dart';
import '../domain/repositories/category_repository.dart';
import '../domain/services/category_inventory_document_builder.dart';

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({
    required this.repository,
    this.productRepository,
    this.documentBuilder,
    required this.user,
    required this.membership,
    super.key,
  });

  final CategoryRepository? repository;
  final ProductRepository? productRepository;
  final CategoryInventoryDocumentBuilder? documentBuilder;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  final _searchController = TextEditingController();

  List<Category> _categories = const <Category>[];
  bool _isLoading = true;
  bool _isExporting = false;
  bool _isSaving = false;
  String? _errorMessage;

  bool get _canManage => widget.membership.role.canManageInventory;

  StoreContext get _storeContext {
    return StoreContext(
      storeId: widget.membership.storeId,
      userId: widget.user.id,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    if (repository == null) {
      return const Center(
        child: Text('مستودع التصنيفات غير موصول بهذه البيئة.'),
      );
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return _buildErrorState();
    }

    final rows = _visibleRows;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('لا توجد تصنيفات مطابقة.'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return _buildCategoryTile(context, row);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<_CategoryRow> get _visibleRows {
    final search = _searchController.text.trim().toLowerCase();
    if (search.isNotEmpty) {
      return _categories
          .where((category) => category.name.toLowerCase().contains(search))
          .map((category) => _CategoryRow(category: category, depth: 0))
          .toList(growable: false);
    }

    final byParent = <String?, List<Category>>{};
    for (final category in _categories) {
      byParent.putIfAbsent(category.parentId, () => <Category>[]).add(category);
    }
    for (final children in byParent.values) {
      children.sort((left, right) {
        final order = left.sortOrder.compareTo(right.sortOrder);
        return order == 0 ? left.name.compareTo(right.name) : order;
      });
    }

    final rows = <_CategoryRow>[];
    final visited = <String>{};

    void append(String? parentId, int depth) {
      for (final category in byParent[parentId] ?? const <Category>[]) {
        if (!visited.add(category.id)) {
          continue;
        }
        rows.add(_CategoryRow(category: category, depth: depth));
        append(category.id, depth + 1);
      }
    }

    append(null, 0);
    for (final category in _categories) {
      if (visited.add(category.id)) {
        rows.add(_CategoryRow(category: category, depth: 0));
      }
    }
    return rows;
  }

  Widget _buildHeader(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.category_outlined),
            const SizedBox(width: 10),
            Text('التصنيفات', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'ابحث باسم التصنيف',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loadCategories,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'طباعة تقرير المخزون',
              onPressed: _isExporting ||
                      widget.productRepository == null ||
                      widget.documentBuilder == null ||
                      _categories.isEmpty
                  ? null
                  : () => _exportInventoryReport(share: false),
              icon: _isExporting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.print_outlined),
            ),
            IconButton(
              tooltip: 'مشاركة تقرير المخزون',
              onPressed: _isExporting ||
                      widget.productRepository == null ||
                      widget.documentBuilder == null ||
                      _categories.isEmpty
                  ? null
                  : () => _exportInventoryReport(share: true),
              icon: const Icon(Icons.share_outlined),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: _canManage && !_isSaving ? () => _openEditor() : null,
              icon: const Icon(Icons.add),
              label: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryTile(BuildContext context, _CategoryRow row) {
    final category = row.category;
    return Card(
      margin: EdgeInsetsDirectional.fromSTEB(12 + row.depth * 24, 3, 12, 3),
      child: ListTile(
        leading: Icon(
          category.isRoot
              ? Icons.folder_outlined
              : Icons.subdirectory_arrow_left_outlined,
        ),
        title: Text(category.name),
        subtitle: Text(category.isActive ? 'نشط' : 'غير نشط'),
        trailing: IconButton(
          tooltip: 'تعديل',
          onPressed:
              _canManage && !_isSaving ? () => _openEditor(category) : null,
          icon: const Icon(Icons.edit_outlined),
        ),
      ),
    );
  }

  Future<void> _openEditor([Category? initialCategory]) async {
    final repository = widget.repository;
    if (repository == null || !_canManage || _isSaving) {
      _showMessage('تعديل التصنيفات غير متاح بصلاحياتك الحالية.');
      return;
    }

    final category = await showDialog<Category>(
      context: context,
      builder: (_) => _CategoryEditorDialog(
        storeId: widget.membership.storeId,
        categories: _categories,
        initialCategory: initialCategory,
      ),
    );
    if (!mounted || category == null) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      final result = await repository.saveCategory(
        context: _storeContext,
        category: category,
      );
      if (!mounted) return;
      if (result is FailureResult<void>) {
        _showMessage(result.failure.message);
        return;
      }
      if (result is Success<void>) {
        await _loadCategories();
        if (mounted) {
          _showMessage(
            initialCategory == null
                ? 'تمت إضافة التصنيف.'
                : 'تم تحديث التصنيف.',
          );
        }
      }
    } catch (error) {
      if (mounted) _showMessage('تعذر حفظ التصنيف: $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _exportInventoryReport({required bool share}) async {
    final productRepository = widget.productRepository;
    final documentBuilder = widget.documentBuilder;
    if (productRepository == null || documentBuilder == null) {
      _showMessage('تصدير تقرير المخزون غير موصول بهذه البيئة.');
      return;
    }

    setState(() => _isExporting = true);
    try {
      final result = await productRepository.getProducts(
        context: _storeContext,
        includeInactive: true,
      );
      if (!mounted) {
        return;
      }
      if (result is FailureResult<List<Product>>) {
        _showMessage(result.failure.message);
        return;
      }

      final products = (result as Success<List<Product>>).value;
      final productsByCategory = <String, List<Product>>{};
      for (final product in products) {
        productsByCategory
            .putIfAbsent(product.categoryId, () => <Product>[])
            .add(product);
      }
      final bytes = await documentBuilder.buildInventoryByCategory(
        categories: _categories,
        productsByCategory: productsByCategory,
        storeName: widget.membership.storeId,
      );
      final filename =
          'category_inventory_${DateTime.now().millisecondsSinceEpoch}';
      if (share) {
        await Printing.sharePdf(bytes: bytes, filename: '$filename.pdf');
      } else {
        await Printing.layoutPdf(onLayout: (_) async => bytes);
      }
    } catch (error) {
      _showMessage('تعذر تجهيز تقرير المخزون: $error');
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _loadCategories() async {
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
    final result = await repository.getCategories(
      context: _storeContext,
      includeInactive: true,
    );
    if (!mounted) {
      return;
    }

    if (result is FailureResult<List<Category>>) {
      setState(() {
        _isLoading = false;
        _errorMessage = result.failure.message;
      });
      return;
    }
    if (result is Success<List<Category>>) {
      setState(() {
        _isLoading = false;
        _categories = result.value;
      });
    }
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
            onPressed: _loadCategories,
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
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
    super.dispose();
  }
}

class _CategoryEditorDialog extends StatefulWidget {
  const _CategoryEditorDialog({
    required this.storeId,
    required this.categories,
    this.initialCategory,
  });

  final String storeId;
  final List<Category> categories;
  final Category? initialCategory;

  @override
  State<_CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<_CategoryEditorDialog> {
  late final TextEditingController _nameController;
  String? _parentId;
  late bool _isActive;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialCategory?.name ?? '',
    );
    _parentId = widget.initialCategory?.parentId;
    _isActive = widget.initialCategory?.isActive ?? true;
  }

  @override
  Widget build(BuildContext context) {
    final initialId = widget.initialCategory?.id;
    final excludedIds = <String>{
      if (initialId != null) initialId,
    };
    // Descendants must not become parents of their own ancestors.
    bool changed;
    do {
      changed = false;
      for (final category in widget.categories) {
        if (category.parentId != null &&
            excludedIds.contains(category.parentId) &&
            excludedIds.add(category.id)) {
          changed = true;
        }
      }
    } while (changed);
    final parentOptions = widget.categories
        .where((category) => !excludedIds.contains(category.id))
        .toList(growable: false);

    return AlertDialog(
      title: Text(
        widget.initialCategory == null ? 'إضافة تصنيف' : 'تعديل التصنيف',
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'اسم التصنيف',
                prefixIcon: Icon(Icons.category_outlined),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _parentId ?? '',
              decoration: const InputDecoration(
                labelText: 'التصنيف الأب',
                prefixIcon: Icon(Icons.account_tree_outlined),
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: '',
                  child: Text('تصنيف رئيسي'),
                ),
                ...parentOptions.map(
                  (category) => DropdownMenuItem<String>(
                    value: category.id,
                    child: Text(category.name),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(
                  () => _parentId = value?.isEmpty == true ? null : value,
                );
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isActive,
              title: const Text('التصنيف نشط'),
              onChanged: (value) => setState(() => _isActive = value),
            ),
            if (_errorMessage != null)
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('حفظ'),
        ),
      ],
    );
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'أدخل اسم التصنيف.');
      return;
    }

    final initial = widget.initialCategory;
    try {
      Navigator.of(context).pop(
        Category(
          id: initial?.id ??
              'category-${DateTime.now().microsecondsSinceEpoch}',
          storeId: widget.storeId,
          name: name,
          parentId: _parentId,
          sortOrder: initial?.sortOrder ?? 0,
          isActive: _isActive,
        ),
      );
    } on ArgumentError catch (error) {
      setState(() => _errorMessage = error.message?.toString());
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}

class _CategoryRow {
  const _CategoryRow({required this.category, required this.depth});

  final Category category;
  final int depth;
}
