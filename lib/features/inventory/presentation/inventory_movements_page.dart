import 'package:flutter/material.dart';

import '../../../../core/idempotency/idempotency_key.dart';
import '../../../../core/money/money.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/result/result.dart';
import '../../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../domain/entities/inventory_movement.dart';
import '../domain/entities/product.dart';
import '../domain/enums/inventory_movement_type.dart';
import '../domain/repositories/inventory_repository.dart';
import '../domain/repositories/product_repository.dart';

class InventoryMovementsPage extends StatefulWidget {
  const InventoryMovementsPage({
    required this.repository,
    required this.productRepository,
    required this.user,
    required this.membership,
    super.key,
  });

  final InventoryRepository? repository;
  final ProductRepository? productRepository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<InventoryMovementsPage> createState() => _InventoryMovementsPageState();
}

class _InventoryMovementsPageState extends State<InventoryMovementsPage> {
  final _quantityController = TextEditingController();
  final _unitCostController = TextEditingController();
  final _descriptionController = TextEditingController();

  List<Product> _products = const <Product>[];
  List<InventoryMovement> _movements = const <InventoryMovement>[];
  Product? _selectedProduct;
  InventoryMovementType _movementType = InventoryMovementType.openingBalance;
  bool _increaseOnAdjustment = true;
  bool _isLoadingProducts = true;
  bool _isLoadingMovements = false;
  bool _isPosting = false;
  String? _errorMessage;

  StoreContext get _storeContext {
    return StoreContext(
      storeId: widget.membership.storeId,
      userId: widget.user.id,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.repository == null || widget.productRepository == null) {
      return const Center(
        child: Text('مستودع المخزون غير موصول بهذه البيئة بعد.'),
      );
    }
    if (_isLoadingProducts) {
      return const Center(child: CircularProgressIndicator());
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: RefreshIndicator(
        onRefresh: _loadProducts,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildHeader(context),
            const SizedBox(height: 12),
            _buildMovementForm(context),
            const SizedBox(height: 12),
            _buildHistory(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(Icons.swap_vert_outlined, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'حركات وأرصدة المخزون',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'كل تعديل يمر بحركة ذرية؛ لا يوجد تعديل مباشر للرصيد.',
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loadProducts,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMovementForm(BuildContext context) {
    if (_products.isEmpty || _selectedProduct == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('أضف صنفاً مخزونياً أولاً من شاشة الأصناف.'),
        ),
      );
    }

    final product = _selectedProduct!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'تسجيل حركة',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Product>(
              initialValue: product,
              decoration: const InputDecoration(
                labelText: 'الصنف',
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
              items: _products
                  .map(
                    (item) => DropdownMenuItem<Product>(
                      value: item,
                      child: Text(item.name),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _isPosting
                  ? null
                  : (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _selectedProduct = value;
                      });
                      _loadMovements();
                    },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<InventoryMovementType>(
              initialValue: _movementType,
              decoration: const InputDecoration(
                labelText: 'نوع الحركة',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: const [
                DropdownMenuItem(
                  value: InventoryMovementType.openingBalance,
                  child: Text('رصيد افتتاحي / إدخال'),
                ),
                DropdownMenuItem(
                  value: InventoryMovementType.adjustment,
                  child: Text('تسوية مخزون'),
                ),
                DropdownMenuItem(
                  value: InventoryMovementType.saleReturn,
                  child: Text('مرتجع بيع / إدخال'),
                ),
                DropdownMenuItem(
                  value: InventoryMovementType.purchaseReturn,
                  child: Text('مرتجع شراء / إخراج'),
                ),
              ],
              onChanged: _isPosting
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _movementType = value);
                      }
                    },
            ),
            if (_movementType == InventoryMovementType.adjustment) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<bool>(
                initialValue: _increaseOnAdjustment,
                decoration: const InputDecoration(
                  labelText: 'اتجاه التسوية',
                  prefixIcon: Icon(Icons.compare_arrows_outlined),
                ),
                items: const [
                  DropdownMenuItem(
                    value: true,
                    child: Text('زيادة الكمية'),
                  ),
                  DropdownMenuItem(
                    value: false,
                    child: Text('نقصان الكمية'),
                  ),
                ],
                onChanged: _isPosting
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _increaseOnAdjustment = value);
                        }
                      },
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantityController,
                    enabled: !_isPosting,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'الكمية',
                      prefixIcon: Icon(Icons.numbers_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _unitCostController,
                    enabled: !_isPosting,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'تكلفة الوحدة',
                      prefixIcon: Icon(Icons.price_change_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              enabled: !_isPosting,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'الوصف أو سبب الحركة',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'الرصيد الحالي: ${product.quantityOnHand.formatted}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _isPosting ? null : _postMovement,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('ترحيل الحركة'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistory(BuildContext context) {
    if (_selectedProduct == null) {
      return const SizedBox.shrink();
    }
    if (_isLoadingMovements) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_movements.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('لا توجد حركات مسجلة لهذا الصنف.'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'آخر الحركات',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final movement in _movements)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  movement.quantityDelta.isNegative
                      ? Icons.remove_circle_outline
                      : Icons.add_circle_outline,
                  color: movement.quantityDelta.isNegative
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                ),
                title: Text(_movementTypeLabel(movement.type)),
                subtitle: Text("${_dateLabel(movement.occurredAt)} • ${movement.sourceType.isEmpty ? 'حركة يدوية' : movement.sourceType}"),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      (movement.quantityDelta.isNegative ? '' : '+') +
                          movement.quantityDelta.formatted,
                    ),
                    Text(movement.totalCost.formatted),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadProducts() async {
    final productRepository = widget.productRepository;
    if (productRepository == null) {
      return;
    }

    setState(() {
      _isLoadingProducts = true;
      _errorMessage = null;
    });
    final previousProductId = _selectedProduct?.id;
    final result = await productRepository.getProducts(context: _storeContext);
    if (!mounted) {
      return;
    }

    if (result is FailureResult<List<Product>>) {
      setState(() {
        _isLoadingProducts = false;
        _errorMessage = result.failure.message;
      });
      return;
    }
    if (result is Success<List<Product>>) {
      final products = result.value
          .where((product) => !product.isService && product.isActive)
          .toList(growable: false);
      Product? selected;
      for (final product in products) {
        if (product.id == previousProductId) {
          selected = product;
          break;
        }
      }
      selected ??= products.isEmpty ? null : products.first;
      setState(() {
        _isLoadingProducts = false;
        _products = products;
        _selectedProduct = selected;
        _movements = const <InventoryMovement>[];
      });
      if (selected != null) {
        await _loadMovements();
      }
    }
  }

  Future<void> _loadMovements() async {
    final inventoryRepository = widget.repository;
    final product = _selectedProduct;
    if (inventoryRepository == null || product == null) {
      return;
    }

    setState(() => _isLoadingMovements = true);
    final result = await inventoryRepository.getMovements(
      context: _storeContext,
      productId: product.id,
    );
    if (!mounted) {
      return;
    }

    if (result is FailureResult<List<InventoryMovement>>) {
      setState(() {
        _isLoadingMovements = false;
        _errorMessage = result.failure.message;
      });
      return;
    }
    if (result is Success<List<InventoryMovement>>) {
      setState(() {
        _isLoadingMovements = false;
        _movements = result.value;
      });
    }
  }

  Future<void> _postMovement() async {
    final inventoryRepository = widget.repository;
    final product = _selectedProduct;
    if (inventoryRepository == null || product == null) {
      return;
    }

    final quantity = _parseQuantity(_quantityController.text);
    final unitCost = _parseMoney(_unitCostController.text);
    if (quantity == null ||
        quantity.isZero ||
        quantity.isNegative ||
        unitCost == null ||
        unitCost.isNegative) {
      setState(() => _errorMessage = 'تحقق من الكمية وتكلفة الوحدة.');
      return;
    }

    final direction = _movementType == InventoryMovementType.purchaseReturn ||
            (_movementType == InventoryMovementType.adjustment &&
                !_increaseOnAdjustment)
        ? -1
        : 1;
    final signedQuantity = Quantity.fromMilliUnits(
      quantity.milliUnits * direction,
    );
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final movement = InventoryMovement(
      id: ['inventory-movement-', now].join(),
      storeId: widget.membership.storeId,
      productId: product.id,
      type: _movementType,
      quantityDelta: signedQuantity,
      unitCost: unitCost,
      idempotencyKey: IdempotencyKey(['inventory-', now].join()),
      sourceType: 'manual_inventory',
      sourceId: null,
      occurredAt: DateTime.now().toUtc(),
    );

    setState(() {
      _isPosting = true;
      _errorMessage = null;
    });
    final result = await inventoryRepository.postMovement(
      context: _storeContext,
      movement: movement,
    );
    if (!mounted) {
      return;
    }

    setState(() => _isPosting = false);
    if (result is FailureResult<InventoryMovement>) {
      _showMessage(result.failure.message);
      return;
    }
    if (result is Success<InventoryMovement>) {
      _quantityController.clear();
      _unitCostController.clear();
      _descriptionController.clear();
      _showMessage('تم ترحيل حركة المخزون.');
      await _loadProducts();
    }
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

  String _movementTypeLabel(InventoryMovementType type) {
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

  String _dateLabel(DateTime date) {
    final local = date.toLocal();
    return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _unitCostController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}
