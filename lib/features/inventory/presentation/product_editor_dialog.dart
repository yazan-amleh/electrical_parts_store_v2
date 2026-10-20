import 'package:flutter/material.dart';

import '../../../core/money/money.dart';
import '../../../core/quantity/quantity.dart';
import '../../categories/domain/entities/category.dart';
import '../domain/entities/product.dart';

class ProductEditorDialog extends StatefulWidget {
  const ProductEditorDialog({
    required this.storeId,
    this.initialProduct,
    this.categories = const <Category>[],
    super.key,
  });

  final String storeId;
  final Product? initialProduct;
  final List<Category> categories;

  @override
  State<ProductEditorDialog> createState() => _ProductEditorDialogState();
}

class _ProductEditorDialogState extends State<ProductEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late final TextEditingController _purchasePriceController;
  late final TextEditingController _sellingPriceController;
  late final TextEditingController _wholesalePriceController;
  late final TextEditingController _minimumQuantityController;
  late final TextEditingController _skuController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _baseUnitIdController;
  late final TextEditingController _baseUnitNameController;
  late final TextEditingController _descriptionController;

  late bool _isService;
  late bool _isActive;
  String? _selectedCategoryId;
  String? _errorMessage;

  Product? get _initialProduct => widget.initialProduct;

  @override
  void initState() {
    super.initState();
    final product = _initialProduct;
    _nameController = TextEditingController(text: product?.name ?? '');
    _categoryController = TextEditingController(
      text: product?.categoryId ?? 'general',
    );
    _selectedCategoryId = product?.categoryId;
    _purchasePriceController = TextEditingController(
      text: product?.purchasePrice.formatted.split(' ').first ?? '',
    );
    _sellingPriceController = TextEditingController(
      text: product?.sellingPrice.formatted.split(' ').first ?? '',
    );
    _wholesalePriceController = TextEditingController(
      text: product?.wholesalePrice.formatted.split(' ').first ?? '',
    );
    _minimumQuantityController = TextEditingController(
      text: product == null
          ? '0'
          : (product.minimumQuantity.milliUnits / Quantity.scale).toString(),
    );
    _skuController = TextEditingController(text: product?.sku ?? '');
    _barcodeController = TextEditingController(text: product?.barcode ?? '');
    _baseUnitIdController = TextEditingController(
      text: product?.baseUnitId ?? 'piece',
    );
    _baseUnitNameController = TextEditingController(
      text: product?.baseUnitName ?? 'قطعة',
    );
    _descriptionController = TextEditingController(
      text: product?.description ?? '',
    );
    _isService = product?.isService ?? false;
    _isActive = product?.isActive ?? true;
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = _initialProduct != null;
    return AlertDialog(
      title: Text(isEditing ? 'تعديل الصنف' : 'إضافة صنف'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _textField(
                _nameController,
                'اسم الصنف',
                Icons.inventory_2_outlined,
              ),
              _buildCategoryField(),
              Row(
                children: [
                  Expanded(
                    child: _textField(
                      _purchasePriceController,
                      'سعر الشراء',
                      Icons.shopping_cart_outlined,
                      decimal: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _textField(
                      _sellingPriceController,
                      'سعر البيع',
                      Icons.sell_outlined,
                      decimal: true,
                    ),
                  ),
                ],
              ),
              _textField(
                _wholesalePriceController,
                'سعر الجملة',
                Icons.storefront_outlined,
                decimal: true,
              ),
              _textField(
                _minimumQuantityController,
                'حد إعادة الطلب',
                Icons.warning_amber_outlined,
                decimal: true,
              ),
              Row(
                children: [
                  Expanded(
                    child: _textField(
                      _baseUnitIdController,
                      'معرّف الوحدة',
                      Icons.straighten_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _textField(
                      _baseUnitNameController,
                      'اسم الوحدة',
                      Icons.label_outline,
                    ),
                  ),
                ],
              ),
              _textField(_skuController, 'SKU', Icons.qr_code_2_outlined),
              _textField(_barcodeController, 'الباركود', Icons.barcode_reader),
              _textField(
                _descriptionController,
                'الوصف',
                Icons.notes_outlined,
                maxLines: 2,
              ),
              SwitchListTile(
                value: _isService,
                title: const Text('هذا المنتج خدمة'),
                subtitle: const Text('الخدمة لا تخصم من المخزون عند البيع.'),
                onChanged: (value) => setState(() => _isService = value),
              ),
              SwitchListTile(
                value: _isActive,
                title: const Text('الصنف نشط'),
                onChanged: (value) => setState(() => _isActive = value),
              ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
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

  Widget _buildCategoryField() {
    if (widget.categories.isEmpty) {
      return _textField(
        _categoryController,
        'معرّف التصنيف',
        Icons.category_outlined,
      );
    }

    final currentId = _selectedCategoryId;
    final hasCurrent =
        currentId != null &&
        widget.categories.any((category) => category.id == currentId);
    final items = <DropdownMenuItem<String>>[
      if (!hasCurrent && currentId != null && currentId.isNotEmpty)
        DropdownMenuItem<String>(
          value: currentId,
          child: Text('تصنيف سابق: $currentId'),
        ),
      ...widget.categories.map(
        (category) => DropdownMenuItem<String>(
          value: category.id,
          child: Text(category.name),
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        initialValue: currentId ?? items.first.value,
        decoration: const InputDecoration(
          labelText: 'التصنيف',
          prefixIcon: Icon(Icons.category_outlined),
        ),
        items: items,
        onChanged: (value) {
          setState(() => _selectedCategoryId = value);
        },
      ),
    );
  }

  Widget _textField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool decimal = false,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: decimal
            ? const TextInputType.numberWithOptions(decimal: true)
            : null,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      ),
    );
  }

  Money? _parseMoney(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      return null;
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
    return Money(
      minorUnits: int.parse(parts.first) * 100 + fraction,
      currency: 'ILS',
    );
  }

  Quantity? _parseQuantity(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      return null;
    }
    final parts = normalized.split('.');
    if (parts.length > 2 ||
        parts.first.isEmpty ||
        int.tryParse(parts.first) == null ||
        (parts.length == 2 &&
            parts[1].isNotEmpty &&
            (parts[1].length > 3 || int.tryParse(parts[1]) == null))) {
      return null;
    }

    final fraction = parts.length == 1 || parts[1].isEmpty
        ? 0
        : int.parse(parts[1].padRight(3, '0'));
    return Quantity.fromMilliUnits(int.parse(parts.first) * 1000 + fraction);
  }

  void _save() {
    final name = _nameController.text.trim();
    final categoryId = widget.categories.isEmpty
        ? _categoryController.text.trim()
        : (_selectedCategoryId ?? '').trim();
    final purchasePrice = _parseMoney(_purchasePriceController.text);
    final sellingPrice = _parseMoney(_sellingPriceController.text);
    final wholesalePrice = _parseMoney(_wholesalePriceController.text);
    final minimumQuantity = _parseQuantity(_minimumQuantityController.text);
    final baseUnitId = _baseUnitIdController.text.trim();
    final baseUnitName = _baseUnitNameController.text.trim();

    if (name.isEmpty ||
        categoryId.isEmpty ||
        baseUnitId.isEmpty ||
        baseUnitName.isEmpty) {
      setState(() => _errorMessage = 'أكمل الحقول الأساسية.');
      return;
    }
    if (purchasePrice == null ||
        sellingPrice == null ||
        wholesalePrice == null ||
        minimumQuantity == null ||
        purchasePrice.isNegative ||
        sellingPrice.isNegative ||
        wholesalePrice.isNegative) {
      setState(() => _errorMessage = 'تحقق من الأسعار والكمية.');
      return;
    }

    try {
      final product = _initialProduct;
      final productId =
          product?.id ??
          ['product-', DateTime.now().microsecondsSinceEpoch].join();
      Navigator.of(context).pop(
        Product(
          id: productId,
          storeId: widget.storeId,
          name: name,
          purchasePrice: purchasePrice,
          sellingPrice: sellingPrice,
          wholesalePrice: wholesalePrice,
          quantityOnHand:
              product?.quantityOnHand ?? const Quantity.fromMilliUnits(0),
          minimumQuantity: minimumQuantity,
          categoryId: categoryId,
          inventoryValue:
              product?.inventoryValue ??
              Money.zero(currency: purchasePrice.currency),
          supplierId: product?.supplierId,
          imageUrl: product?.imageUrl ?? '',
          brand: product?.brand,
          model: product?.model,
          location: product?.location,
          shelf: product?.shelf,
          discountable: product?.discountable ?? true,
          expiryDate: product?.expiryDate,
          units: product?.units ?? const [],
          description: _descriptionController.text.trim(),
          barcode: _emptyToNull(_barcodeController.text),
          sku: _emptyToNull(_skuController.text),
          baseUnitId: baseUnitId,
          baseUnitName: baseUnitName,
          isService: _isService,
          isActive: _isActive,
        ),
      );
    } on ArgumentError catch (error) {
      setState(() => _errorMessage = error.message.toString());
    }
  }

  String? _emptyToNull(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _purchasePriceController.dispose();
    _sellingPriceController.dispose();
    _wholesalePriceController.dispose();
    _minimumQuantityController.dispose();
    _skuController.dispose();
    _barcodeController.dispose();
    _baseUnitIdController.dispose();
    _baseUnitNameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}
