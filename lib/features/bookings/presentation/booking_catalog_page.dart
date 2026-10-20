import 'package:flutter/material.dart';

import '../../../core/money/money.dart';
import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../../auth/domain/enums/store_role.dart';
import '../domain/entities/booking_customer.dart';
import '../domain/entities/photography_option.dart';
import '../domain/repositories/booking_catalog_repository.dart';

class BookingCatalogPage extends StatefulWidget {
  const BookingCatalogPage({
    required this.repository,
    required this.user,
    required this.membership,
    super.key,
  });

  final BookingCatalogRepository? repository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<BookingCatalogPage> createState() => _BookingCatalogPageState();
}

class _BookingCatalogPageState extends State<BookingCatalogPage> {
  final _searchController = TextEditingController();
  int _selectedTab = 0;

  StoreContext get _storeContext {
    return StoreContext(
      storeId: widget.membership.storeId,
      userId: widget.user.id,
    );
  }

  bool get _canManageCatalog {
    return widget.membership.role.canManageSales ||
        widget.membership.role.canPostAccounting;
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    if (repository == null) {
      return const Center(
        child: Text('مستودع كتالوج الحجوزات غير موصول بهذه البيئة.'),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: _selectedTab == 0
                ? _buildCustomers(repository)
                : _buildOptions(repository),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.event_available_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'الحجوزات والتصوير',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (_canManageCatalog)
                  FilledButton.icon(
                    onPressed: _openEditor,
                    icon: const Icon(Icons.add),
                    label: Text(_selectedTab == 0 ? 'عميل' : 'خيار تصوير'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment<int>(
                  value: 0,
                  icon: Icon(Icons.people_outline),
                  label: Text('عملاء الحجوزات'),
                ),
                ButtonSegment<int>(
                  value: 1,
                  icon: Icon(Icons.camera_alt_outlined),
                  label: Text('خيارات التصوير'),
                ),
              ],
              selected: {_selectedTab},
              onSelectionChanged: (selection) {
                setState(() {
                  _selectedTab = selection.first;
                  _searchController.clear();
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'ابحث بالاسم أو الهاتف أو الوصف',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomers(BookingCatalogRepository repository) {
    return StreamBuilder<Result<List<BookingCustomer>>>(
      stream: repository.watchCustomers(context: _storeContext),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _errorState(snapshot.error.toString());
        }
        final result = snapshot.data;
        if (result == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (result is FailureResult<List<BookingCustomer>>) {
          return _errorState(result.failure.message);
        }
        final customers = (result as Success<List<BookingCustomer>>).value
            .where(_customerMatches)
            .toList(growable: false);
        if (customers.isEmpty) {
          return const Center(child: Text('لا يوجد عملاء حجوزات بعد.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          itemCount: customers.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final customer = customers[index];
            return Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.person_outline),
                ),
                title: Text(customer.name),
                subtitle: Text(
                  [
                    customer.phoneNumber,
                    if (customer.email?.isNotEmpty == true) customer.email!,
                    if (customer.address?.isNotEmpty == true)
                      customer.address!,
                  ].join(' • '),
                ),
                trailing: _canManageCatalog
                    ? IconButton(
                        tooltip: 'تعديل',
                        onPressed: () => _openEditor(customer: customer),
                        icon: const Icon(Icons.edit_outlined),
                      )
                    : null,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildOptions(BookingCatalogRepository repository) {
    return StreamBuilder<Result<List<PhotographyOption>>>(
      stream: repository.watchOptions(context: _storeContext),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _errorState(snapshot.error.toString());
        }
        final result = snapshot.data;
        if (result == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (result is FailureResult<List<PhotographyOption>>) {
          return _errorState(result.failure.message);
        }
        final options = (result as Success<List<PhotographyOption>>).value
            .where(_optionMatches)
            .toList(growable: false);
        if (options.isEmpty) {
          return const Center(child: Text('لا توجد خيارات تصوير بعد.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          itemCount: options.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final option = options[index];
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Icon(
                    option.isActive
                        ? Icons.camera_alt_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
                title: Text(option.name),
                subtitle: Text(
                  [
                    option.price.formatted,
                    if (option.durationMinutes > 0)
                      '${option.durationMinutes} دقيقة',
                    if (option.description.trim().isNotEmpty)
                      option.description.trim(),
                    option.isActive ? 'نشط' : 'غير نشط',
                  ].join(' • '),
                ),
                trailing: _canManageCatalog
                    ? IconButton(
                        tooltip: 'تعديل',
                        onPressed: () => _openEditor(option: option),
                        icon: const Icon(Icons.edit_outlined),
                      )
                    : null,
              ),
            );
          },
        );
      },
    );
  }

  bool _customerMatches(BookingCustomer customer) {
    final search = _searchController.text.trim().toLowerCase();
    return search.isEmpty ||
        customer.name.toLowerCase().contains(search) ||
        customer.phoneNumber.toLowerCase().contains(search) ||
        (customer.email?.toLowerCase().contains(search) ?? false);
  }

  bool _optionMatches(PhotographyOption option) {
    final search = _searchController.text.trim().toLowerCase();
    return search.isEmpty ||
        option.name.toLowerCase().contains(search) ||
        option.description.toLowerCase().contains(search);
  }

  Future<void> _openEditor({
    BookingCustomer? customer,
    PhotographyOption? option,
  }) async {
    final repository = widget.repository;
    if (repository == null || !_canManageCatalog) {
      return;
    }

    if (_selectedTab == 0) {
      final value = await showDialog<BookingCustomer>(
        context: context,
        builder: (_) => _BookingCustomerDialog(
          storeId: widget.membership.storeId,
          initial: customer,
        ),
      );
      if (!mounted || value == null) {
        return;
      }
      final result = await repository.saveCustomer(
        context: _storeContext,
        customer: value,
      );
      if (mounted) {
        _showResult(result, customer == null ? 'تمت إضافة العميل.' : 'تم تحديث العميل.');
      }
      return;
    }

    final value = await showDialog<PhotographyOption>(
      context: context,
      builder: (_) => _PhotographyOptionDialog(
        storeId: widget.membership.storeId,
        initial: option,
      ),
    );
    if (!mounted || value == null) {
      return;
    }
    final result = await repository.saveOption(
      context: _storeContext,
      option: value,
    );
    if (mounted) {
      _showResult(result, option == null ? 'تمت إضافة خيار التصوير.' : 'تم تحديث خيار التصوير.');
    }
  }

  void _showResult<T>(Result<T> result, String successMessage) {
    final message = result is FailureResult<T>
        ? result.failure.message
        : successMessage;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _errorState(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

class _BookingCustomerDialog extends StatefulWidget {
  const _BookingCustomerDialog({required this.storeId, this.initial});

  final String storeId;
  final BookingCustomer? initial;

  @override
  State<_BookingCustomerDialog> createState() => _BookingCustomerDialogState();
}

class _BookingCustomerDialogState extends State<_BookingCustomerDialog> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _address;
  late final TextEditingController _notes;
  String? _error;

  @override
  void initState() {
    super.initState();
    final value = widget.initial;
    _name = TextEditingController(text: value?.name ?? '');
    _phone = TextEditingController(text: value?.phoneNumber ?? '');
    _email = TextEditingController(text: value?.email ?? '');
    _address = TextEditingController(text: value?.address ?? '');
    _notes = TextEditingController(text: value?.notes ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'إضافة عميل حجز' : 'تعديل عميل الحجز'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(_name, 'الاسم', Icons.person_outline),
              _field(_phone, 'الهاتف', Icons.phone_outlined),
              _field(_email, 'البريد الإلكتروني', Icons.email_outlined),
              _field(_address, 'العنوان', Icons.location_on_outlined),
              _field(_notes, 'ملاحظات', Icons.notes_outlined, maxLines: 2),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
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

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      ),
    );
  }

  void _save() {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty || phone.isEmpty) {
      setState(() => _error = 'الاسم والهاتف مطلوبان.');
      return;
    }
    try {
      final initial = widget.initial;
      Navigator.of(context).pop(
        BookingCustomer(
          id: initial?.id ?? 'booking-customer-${DateTime.now().microsecondsSinceEpoch}',
          storeId: widget.storeId,
          name: name,
          phoneNumber: phone,
          email: _empty(_email.text),
          address: _empty(_address.text),
          notes: _empty(_notes.text),
          createdAt: initial?.createdAt ?? DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    } on ArgumentError catch (error) {
      setState(() => _error = error.message?.toString());
    }
  }

  String? _empty(String value) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }
}

class _PhotographyOptionDialog extends StatefulWidget {
  const _PhotographyOptionDialog({required this.storeId, this.initial});

  final String storeId;
  final PhotographyOption? initial;

  @override
  State<_PhotographyOptionDialog> createState() =>
      _PhotographyOptionDialogState();
}

class _PhotographyOptionDialogState extends State<_PhotographyOptionDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _duration;
  late bool _isActive;
  String? _error;

  @override
  void initState() {
    super.initState();
    final value = widget.initial;
    _name = TextEditingController(text: value?.name ?? '');
    _description = TextEditingController(text: value?.description ?? '');
    _price = TextEditingController(
      text: value == null ? '' : (value.price.minorUnits / 100).toStringAsFixed(2),
    );
    _duration = TextEditingController(
      text: value == null ? '0' : value.durationMinutes.toString(),
    );
    _isActive = value?.isActive ?? true;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'إضافة خيار تصوير' : 'تعديل خيار التصوير'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(_name, 'اسم الخيار', Icons.camera_alt_outlined),
              _field(_description, 'الوصف', Icons.description_outlined, maxLines: 2),
              _field(
                _price,
                'السعر (شيكل)',
                Icons.payments_outlined,
                decimal: true,
              ),
              _field(
                _duration,
                'المدة بالدقائق',
                Icons.schedule_outlined,
                decimal: false,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isActive,
                title: const Text('الخيار نشط'),
                onChanged: (value) => setState(() => _isActive = value),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
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

  Widget _field(
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
        keyboardType: maxLines > 1
            ? null
            : decimal
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.number,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      ),
    );
  }

  void _save() {
    final name = _name.text.trim();
    final price = _parseMoney(_price.text);
    final duration = int.tryParse(_duration.text.trim());
    if (name.isEmpty || price == null || price.isNegative || duration == null || duration < 0) {
      setState(() => _error = 'تحقق من الاسم والسعر والمدة.');
      return;
    }
    try {
      final initial = widget.initial;
      Navigator.of(context).pop(
        PhotographyOption(
          id: initial?.id ?? 'photography-option-${DateTime.now().microsecondsSinceEpoch}',
          storeId: widget.storeId,
          name: name,
          description: _description.text.trim(),
          price: price,
          durationMinutes: duration,
          isActive: _isActive,
          createdAt: initial?.createdAt ?? DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    } on ArgumentError catch (error) {
      setState(() => _error = error.message?.toString());
    }
  }

  Money? _parseMoney(String raw) {
    final value = raw.trim().replaceAll(',', '.');
    if (value.isEmpty) {
      return null;
    }
    final parts = value.split('.');
    if (parts.length > 2 || int.tryParse(parts.first) == null) {
      return null;
    }
    final fraction = parts.length == 1 || parts[1].isEmpty
        ? 0
        : int.tryParse(parts[1].padRight(2, '0'));
    if (fraction == null || (parts.length == 2 && parts[1].length > 2)) {
      return null;
    }
    return Money(
      minorUnits: int.parse(parts.first) * 100 + fraction,
      currency: 'ILS',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _duration.dispose();
    super.dispose();
  }
}
