import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../data/exporters/pdf_product_history_document_builder.dart';
import '../domain/entities/inventory_movement.dart';
import '../domain/entities/product.dart';
import '../domain/enums/inventory_movement_type.dart';
import '../domain/repositories/inventory_repository.dart';
import '../domain/repositories/product_repository.dart';

/// V1-style read-only product details. No balances or journal entries are
/// modified from this screen; editing is an explicitly permissioned action.
class ProductDetailsPage extends StatefulWidget {
  const ProductDetailsPage({
    required this.productId,
    required this.contextScope,
    required this.productRepository,
    this.inventoryRepository,
    this.onEdit,
    super.key,
  });

  final String productId;
  final StoreContext contextScope;
  final ProductRepository productRepository;
  final InventoryRepository? inventoryRepository;
  final VoidCallback? onEdit;

  @override
  State<ProductDetailsPage> createState() => _ProductDetailsPageState();
}

class _ProductDetailsPageState extends State<ProductDetailsPage> {
  static const _limit = 500;
  Product? _product;
  List<InventoryMovement> _movements = const [];
  InventoryMovementType? _filterType;
  String _search = '';
  DateTimeRange? _dateRange;
  bool _loading = true;
  bool _exporting = false;
  String? _error;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ProductDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productId != widget.productId ||
        oldWidget.contextScope.storeId != widget.contextScope.storeId ||
        oldWidget.contextScope.userId != widget.contextScope.userId ||
        oldWidget.productRepository != widget.productRepository ||
        oldWidget.inventoryRepository != widget.inventoryRepository) {
      ++_epoch;
      _product = null;
      _movements = const [];
      _filterType = null;
      _search = '';
      _dateRange = null;
      _load();
    }
  }

  bool _sameContext(int epoch, StoreContext context) =>
      mounted &&
      epoch == _epoch &&
      widget.contextScope.storeId == context.storeId &&
      widget.contextScope.userId == context.userId;

  Future<void> _load() async {
    final epoch = ++_epoch;
    final scope = widget.contextScope;
    final productId = widget.productId;
    final products = widget.productRepository;
    final historyRepository = widget.inventoryRepository;
    setState(() {
      _loading = true;
      _error = null;
      _product = null;
      _movements = const [];
    });
    final result = await products.getProduct(
      context: scope,
      productId: productId,
    );
    if (!_sameContext(epoch, scope) ||
        products != widget.productRepository ||
        productId != widget.productId) {
      return;
    }
    if (result is! Success<Product>) {
      setState(() {
        _loading = false;
        _error = result is FailureResult<Product>
            ? result.failure.message
            : 'تعذر تحميل بيانات الصنف.';
      });
      return;
    }
    if (result.value.id != productId || result.value.storeId != scope.storeId) {
      setState(() {
        _loading = false;
        _error = 'تم رفض بيانات صنف لا يتبع المتجر الحالي.';
      });
      return;
    }
    if (historyRepository == null || result.value.isService) {
      setState(() {
        _loading = false;
        _product = result.value;
      });
      return;
    }
    final history = await historyRepository.getMovements(
      context: scope,
      productId: productId,
      limit: _limit,
    );
    if (!_sameContext(epoch, scope) ||
        historyRepository != widget.inventoryRepository ||
        products != widget.productRepository ||
        productId != widget.productId) {
      return;
    }

    if (history is FailureResult<List<InventoryMovement>>) {
      setState(() {
        _loading = false;
        _product = result.value;
        _error = 'تعذر تحميل الحركات: ${history.failure.message}';
      });
      return;
    }
    if (history is Success<List<InventoryMovement>>) {
      if (history.value.any((movement) =>
          movement.storeId != scope.storeId ||
          movement.productId != productId)) {
        setState(() {
          _loading = false;
          _product = result.value;
          _error = 'تم رفض حركات تخص صنفًا أو متجرًا آخر.';
        });
        return;
      }
      final ordered = [...history.value]
        ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      setState(() {
        _loading = false;
        _product = result.value;
        _movements = ordered;
      });
    }
  }

  List<InventoryMovement> get _visible {
    final query = _search.trim().toLowerCase();
    return _movements.where((movement) {
      if (_filterType != null && movement.type != _filterType) return false;
      final range = _dateRange;
      if (range != null) {
        final date = movement.occurredAt.toLocal();
        final begin =
            DateTime(range.start.year, range.start.month, range.start.day);
        final end = DateTime(range.end.year, range.end.month, range.end.day)
            .add(const Duration(days: 1));
        if (date.isBefore(begin) || !date.isBefore(end)) return false;
      }
      if (query.isNotEmpty &&
          ![
            movement.description,
            movement.sourceType,
            movement.sourceId ?? '',
          ].any((part) => part.toLowerCase().contains(query))) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _print({required bool share}) async {
    final product = _product;
    if (product == null || _loading || _exporting || _error != null) return;
    final scope = widget.contextScope;
    final epoch = _epoch;
    final filtered = _visible;
    setState(() => _exporting = true);
    try {
      final bytes = await PdfProductHistoryDocumentBuilder().build(
        product: product,
        movements: filtered,
        expectedStoreId: scope.storeId,
        historyMayBeTruncated: _movements.length >= _limit,
      );
      if (!_sameContext(epoch, scope)) return;
      final filename = 'product_${product.id}_history.pdf';
      if (share) {
        await Printing.sharePdf(bytes: bytes, filename: filename);
      } else {
        await Printing.layoutPdf(
          name: filename,
          onLayout: (_) async => bytes,
        );
      }
    } catch (_) {
      if (_sameContext(epoch, scope)) {
        _message('تعذر إنشاء ملف تفاصيل الصنف للطباعة.');
      }
    } finally {
      if (_sameContext(epoch, scope)) setState(() => _exporting = false);
    }
  }

  Future<void> _chooseDates() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _dateRange,
    );
    if (mounted && range != null) setState(() => _dateRange = range);
  }

  Widget _info(String label, String value) => ListTile(
        dense: true,
        title: Text(label),
        subtitle: SelectableText(value.isEmpty ? '—' : value),
      );

  Widget _productCard(Product product) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('معلومات الصنف',
                style: Theme.of(context).textTheme.titleLarge),
            Wrap(
              spacing: 12,
              children: [
                SizedBox(width: 220, child: _info('الاسم', product.name)),
                SizedBox(width: 220, child: _info('SKU', product.sku ?? '—')),
                SizedBox(
                    width: 220,
                    child: _info('الباركود', product.barcode ?? '—')),
                SizedBox(
                    width: 220, child: _info('التصنيف', product.categoryId)),
                SizedBox(
                    width: 220,
                    child: _info('العلامة التجارية', product.brand ?? '—')),
                SizedBox(
                    width: 220, child: _info('الموديل', product.model ?? '—')),
                SizedBox(
                    width: 220,
                    child: _info('الموقع', product.location ?? '—')),
                SizedBox(
                    width: 220, child: _info('الرف', product.shelf ?? '—')),
                SizedBox(
                    width: 220,
                    child: _info('الوحدة', product.baseUnitName ?? '—')),
                SizedBox(
                    width: 220,
                    child:
                        _info('سعر الشراء', product.purchasePrice.formatted)),
                SizedBox(
                    width: 220,
                    child:
                        _info('سعر الجملة', product.wholesalePrice.formatted)),
                SizedBox(
                    width: 220,
                    child: _info('سعر البيع', product.sellingPrice.formatted)),
                SizedBox(
                    width: 220,
                    child: _info(
                        'قابل للخصم', product.discountable ? 'نعم' : 'لا')),
                SizedBox(
                    width: 220,
                    child:
                        _info('الحالة', product.isActive ? 'نشط' : 'غير نشط')),
                if (!product.isService) ...[
                  SizedBox(
                      width: 220,
                      child: _info(
                          'الرصيد الحالي', product.quantityOnHand.formatted)),
                  SizedBox(
                      width: 220,
                      child: _info(
                          'الحد الأدنى', product.minimumQuantity.formatted)),
                  SizedBox(
                      width: 220,
                      child: _info('قيمة المخزون المسجلة',
                          product.inventoryValue.formatted)),
                ],
              ],
            ),
            if (product.isLowStock)
              const ListTile(
                leading: Icon(Icons.warning_amber_outlined),
                title: Text('تنبيه: الصنف عند حد إعادة الطلب أو دونه'),
              ),
            if (product.description.trim().isNotEmpty)
              _info('الوصف', product.description),
            if (product.expiryDate != null)
              _info('تاريخ الانتهاء',
                  product.expiryDate!.toLocal().toString().split(' ').first),
            if (product.isService)
              const Text('هذا الصنف خدمة ولا تنطبق عليه حركات المخزون.'),
          ],
        ),
      ),
    );
  }

  Widget _historyCard(Product product) {
    final visible = _visible;
    final incoming = visible
        .where((m) => m.quantityDelta.milliUnits > 0)
        .fold<int>(0, (sum, m) => sum + m.quantityDelta.milliUnits);
    final outgoing = visible
        .where((m) => m.quantityDelta.milliUnits < 0)
        .fold<int>(0, (sum, m) => sum - m.quantityDelta.milliUnits);
    String qty(int milli) => (milli / 1000).toStringAsFixed(3);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('سجل حركات الصنف',
                style: Theme.of(context).textTheme.titleLarge),
            if (_movements.length >= _limit)
              const ListTile(
                leading: Icon(Icons.warning_amber_outlined),
                title: Text('السجل جزئي: آخر 500 حركة فقط'),
                subtitle: Text(
                  'لا يمكن استنتاج الرصيد التاريخي أو رصيد افتتاحي من سجل جزئي.',
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('الحركات المطابقة: ${visible.length}')),
                Chip(label: Text('وارد في المعروض: ${qty(incoming)}')),
                Chip(label: Text('صادر في المعروض: ${qty(outgoing)}')),
              ],
            ),
            Text(
              'الرصيد الحالي من سجل الصنف: ${product.quantityOnHand.formatted}. '
              'مجاميع الوارد والصادر أعلاه ضمن الحركات المعروضة فقط.',
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 240,
                  child: TextField(
                    key: const ValueKey('product-history-search'),
                    decoration: const InputDecoration(
                      labelText: 'بحث في المرجع أو الوصف',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() => _search = value),
                  ),
                ),
                DropdownButton<InventoryMovementType?>(
                  key: const ValueKey('product-history-type'),
                  value: _filterType,
                  hint: const Text('كل أنواع الحركات'),
                  items: [
                    const DropdownMenuItem<InventoryMovementType?>(
                      value: null,
                      child: Text('كل أنواع الحركات'),
                    ),
                    for (final type in InventoryMovementType.values)
                      DropdownMenuItem<InventoryMovementType?>(
                        value: type,
                        child: Text(_typeLabel(type)),
                      ),
                  ],
                  onChanged: (value) => setState(() => _filterType = value),
                ),
                OutlinedButton.icon(
                  onPressed: _chooseDates,
                  icon: const Icon(Icons.date_range),
                  label: Text(_dateRange == null ? 'الفترة' : 'تغيير الفترة'),
                ),
                if (_dateRange != null)
                  TextButton(
                    onPressed: () => setState(() => _dateRange = null),
                    child: const Text('مسح الفترة'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (visible.isEmpty)
              const Text('لا توجد حركات مطابقة للبحث والفلاتر.')
            else
              for (final movement in visible)
                ListTile(
                  leading: Icon(movement.quantityDelta.isNegative
                      ? Icons.remove_circle_outline
                      : Icons.add_circle_outline),
                  title: Text(_typeLabel(movement.type)),
                  subtitle: Text(
                    '${_stamp(movement.occurredAt)} • '
                    '${movement.sourceId ?? movement.sourceType} '
                    '${movement.description}',
                  ),
                  trailing: Text(
                    '${movement.quantityDelta.isNegative ? '' : '+'}'
                    '${movement.quantityDelta.formatted}',
                  ),
                ),
            const SizedBox(height: 8),
            const Text(
              'الحركات المعروضة سجل معلوماتي؛ لا ينتج عنه أي تسوية أو قيد.',
            ),
          ],
        ),
      ),
    );
  }

  static String _stamp(DateTime date) {
    final value = date.toLocal();
    return '${value.year}/${value.month.toString().padLeft(2, '0')}/'
        '${value.day.toString().padLeft(2, '0')}';
  }

  static String _typeLabel(InventoryMovementType type) {
    switch (type) {
      case InventoryMovementType.openingBalance:
        return 'رصيد افتتاحي';
      case InventoryMovementType.purchaseReceipt:
        return 'استلام شراء';
      case InventoryMovementType.saleIssue:
        return 'صرف بيع';
      case InventoryMovementType.purchaseReturn:
        return 'مرتجع شراء';
      case InventoryMovementType.saleReturn:
        return 'مرتجع بيع';
      case InventoryMovementType.adjustment:
        return 'تسوية مخزون';
      case InventoryMovementType.transferIn:
        return 'تحويل وارد';
      case InventoryMovementType.transferOut:
        return 'تحويل صادر';
    }
  }

  @override
  void dispose() {
    ++_epoch;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تفاصيل الصنف'),
          actions: [
            if (widget.onEdit != null)
              IconButton(
                tooltip: 'تعديل الصنف',
                onPressed: widget.onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
            IconButton(
              tooltip: 'تحديث تفاصيل الصنف',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_outlined),
            ),
            IconButton(
              tooltip: 'طباعة كشف الصنف',
              onPressed: _loading ||
                      _exporting ||
                      _error != null ||
                      _product == null ||
                      widget.inventoryRepository == null
                  ? null
                  : () => _print(share: false),
              icon: const Icon(Icons.print_outlined),
            ),
            IconButton(
              tooltip: 'مشاركة PDF للصنف',
              onPressed: _loading ||
                      _exporting ||
                      _error != null ||
                      _product == null ||
                      widget.inventoryRepository == null
                  ? null
                  : () => _print(share: true),
              icon: const Icon(Icons.share_outlined),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _product == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error ?? 'تعذر عرض الصنف.'),
                        TextButton(
                          onPressed: _load,
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _productCard(_product!),
                        if (_error != null)
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.error_outline),
                              title: Text(_error!),
                              trailing: TextButton(
                                onPressed: _load,
                                child: const Text('إعادة المحاولة'),
                              ),
                            ),
                          ),
                        if (widget.inventoryRepository != null &&
                            !_product!.isService) ...[
                          const SizedBox(height: 12),
                          _historyCard(_product!),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }
}
