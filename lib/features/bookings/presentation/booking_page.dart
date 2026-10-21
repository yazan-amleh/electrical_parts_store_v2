import 'package:flutter/material.dart';

import '../../../core/idempotency/idempotency_key.dart';
import '../../../core/money/money.dart';
import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../../auth/domain/enums/store_role.dart';
import '../domain/entities/booking.dart';
import '../domain/entities/booking_customer.dart';
import '../domain/entities/photography_option.dart';
import '../domain/enums/booking_enums.dart';
import '../domain/repositories/booking_catalog_repository.dart';
import '../domain/repositories/booking_repository.dart';
import 'booking_catalog_page.dart';

class BookingPage extends StatefulWidget {
  const BookingPage({
    required this.repository,
    required this.catalogRepository,
    required this.user,
    required this.membership,
    super.key,
  });

  final BookingRepository? repository;
  final BookingCatalogRepository? catalogRepository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  final _searchController = TextEditingController();
  int _selectedTab = 0;

  StoreContext get _storeContext {
    return StoreContext(
      storeId: widget.membership.storeId,
      userId: widget.user.id,
    );
  }

  bool get _canManage {
    return widget.membership.role.canManageSales ||
        widget.membership.role.canPostAccounting;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: _selectedTab == 0
                ? _buildBookings()
                : BookingCatalogPage(
                    repository: widget.catalogRepository,
                    user: widget.user,
                    membership: widget.membership,
                  ),
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
                if (_selectedTab == 0 && _canManage)
                  FilledButton.icon(
                    onPressed: _openBookingEditor,
                    icon: const Icon(Icons.add),
                    label: const Text('حجز جديد'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment<int>(
                  value: 0,
                  icon: Icon(Icons.calendar_month_outlined),
                  label: Text('الحجوزات'),
                ),
                ButtonSegment<int>(
                  value: 1,
                  icon: Icon(Icons.camera_alt_outlined),
                  label: Text('الكتالوج'),
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
            if (_selectedTab == 0) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'ابحث باسم العميل أو الهاتف أو المكان',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBookings() {
    final repository = widget.repository;
    if (repository == null) {
      return const Center(
        child: Text('مستودع الحجوزات غير موصول بهذه البيئة.'),
      );
    }

    return StreamBuilder<Result<List<Booking>>>(
      stream: repository.watchBookings(context: _storeContext),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _errorState(snapshot.error.toString());
        }
        final result = snapshot.data;
        if (result == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (result is FailureResult<List<Booking>>) {
          return _errorState(result.failure.message);
        }
        final bookings = (result as Success<List<Booking>>)
            .value
            .where(_bookingMatches)
            .toList(growable: false);
        if (bookings.isEmpty) {
          return const Center(
            child: Text('لا توجد حجوزات بعد. ابدأ بإضافة أول حجز.'),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          itemCount: bookings.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final booking = bookings[index];
            return Card(
              child: ListTile(
                onTap: _canEdit(booking)
                    ? () => _openBookingEditor(initial: booking)
                    : null,
                leading: CircleAvatar(
                  child: Icon(_statusIcon(booking.status)),
                ),
                title: Text(
                  '${booking.customerName} • ${booking.photographyOptionName}',
                ),
                subtitle: Text(
                  [
                    _formatDateTime(context, booking.startAt),
                    booking.location,
                    booking.totalPrice.formatted,
                    _statusLabel(booking.status),
                  ].join(' • '),
                ),
                isThreeLine: true,
                trailing: _buildStatusMenu(booking),
              ),
            );
          },
        );
      },
    );
  }

  Widget? _buildStatusMenu(Booking booking) {
    if (!_canManage || _nextStatuses(booking.status).isEmpty) {
      return null;
    }
    return PopupMenuButton<BookingStatus>(
      tooltip: 'تغيير الحالة',
      onSelected: (status) => _transition(booking, status),
      itemBuilder: (context) {
        return [
          for (final status in _nextStatuses(booking.status))
            PopupMenuItem<BookingStatus>(
              value: status,
              child: Text(_statusLabel(status)),
            ),
        ];
      },
    );
  }

  bool _bookingMatches(Booking booking) {
    final search = _searchController.text.trim().toLowerCase();
    return search.isEmpty ||
        booking.customerName.toLowerCase().contains(search) ||
        booking.customerPhone.toLowerCase().contains(search) ||
        booking.location.toLowerCase().contains(search) ||
        booking.photographyOptionName.toLowerCase().contains(search);
  }

  bool _canEdit(Booking booking) {
    return _canManage &&
        booking.status != BookingStatus.completed &&
        booking.status != BookingStatus.cancelled;
  }

  Future<void> _openBookingEditor({Booking? initial}) async {
    final repository = widget.repository;
    final catalogRepository = widget.catalogRepository;
    if (repository == null || catalogRepository == null || !_canManage) {
      return;
    }

    final value = await showDialog<Booking>(
      context: context,
      builder: (_) => _BookingEditorDialog(
        storeContext: _storeContext,
        catalogRepository: catalogRepository,
        initial: initial,
      ),
    );
    if (!mounted || value == null) {
      return;
    }

    final result = initial == null
        ? await repository.createBooking(
            context: _storeContext,
            booking: value,
          )
        : await repository.updateBooking(
            context: _storeContext,
            booking: value,
          );
    if (mounted) {
      _showResult(
        result,
        initial == null ? 'تم إنشاء الحجز.' : 'تم تحديث الحجز.',
      );
    }
  }

  Future<void> _transition(Booking booking, BookingStatus status) async {
    final repository = widget.repository;
    if (repository == null) {
      return;
    }
    final result = await repository.transitionBooking(
      context: _storeContext,
      bookingId: booking.id,
      status: status,
    );
    if (mounted) {
      _showResult(result, 'تم تحديث حالة الحجز.');
    }
  }

  void _showResult<T>(Result<T> result, String successMessage) {
    final message =
        result is FailureResult<T> ? result.failure.message : successMessage;
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

  String _formatDateTime(BuildContext context, DateTime value) {
    final local = value.toLocal();
    final date = MaterialLocalizations.of(context).formatMediumDate(local);
    final time = TimeOfDay.fromDateTime(local).format(context);
    return '$date $time';
  }

  IconData _statusIcon(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
        return Icons.hourglass_empty;
      case BookingStatus.confirmed:
        return Icons.check_circle_outline;
      case BookingStatus.completed:
        return Icons.task_alt;
      case BookingStatus.cancelled:
        return Icons.cancel_outlined;
    }
  }

  String _statusLabel(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
        return 'معلّق';
      case BookingStatus.confirmed:
        return 'مؤكد';
      case BookingStatus.completed:
        return 'مكتمل';
      case BookingStatus.cancelled:
        return 'ملغى';
    }
  }

  List<BookingStatus> _nextStatuses(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
        return [BookingStatus.confirmed, BookingStatus.cancelled];
      case BookingStatus.confirmed:
        return [BookingStatus.completed, BookingStatus.cancelled];
      case BookingStatus.completed:
      case BookingStatus.cancelled:
        return const [];
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

class _BookingEditorDialog extends StatefulWidget {
  const _BookingEditorDialog({
    required this.storeContext,
    required this.catalogRepository,
    this.initial,
  });

  final StoreContext storeContext;
  final BookingCatalogRepository catalogRepository;
  final Booking? initial;

  @override
  State<_BookingEditorDialog> createState() => _BookingEditorDialogState();
}

class _BookingEditorDialogState extends State<_BookingEditorDialog> {
  late final Stream<Result<List<BookingCustomer>>> _customers;
  late final Stream<Result<List<PhotographyOption>>> _options;
  late final TextEditingController _location;
  late final TextEditingController _duration;
  late final TextEditingController _discount;
  late final TextEditingController _deposit;
  late final TextEditingController _notes;
  late DateTime _startAt;
  String? _customerId;
  String? _optionId;
  String? _error;
  List<BookingCustomer> _customerCache = const [];
  List<PhotographyOption> _optionCache = const [];

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _customers = widget.catalogRepository.watchCustomers(
      context: widget.storeContext,
    );
    _options = widget.catalogRepository.watchOptions(
      context: widget.storeContext,
    );
    _location = TextEditingController(text: initial?.location ?? '');
    _duration = TextEditingController(
      text: initial?.durationMinutes.toString() ?? '60',
    );
    _discount = TextEditingController(
      text: initial == null
          ? '0'
          : (initial.totalDiscount.minorUnits / 100).toStringAsFixed(2),
    );
    _deposit = TextEditingController(
      text: initial == null
          ? '0'
          : (initial.depositAmount.minorUnits / 100).toStringAsFixed(2),
    );
    _notes = TextEditingController(text: initial?.notes ?? '');
    _startAt = initial?.startAt ?? DateTime.now().add(const Duration(hours: 1));
    _customerId = initial?.customerId;
    _optionId = initial?.photographyOptionId;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'حجز جديد' : 'تعديل الحجز'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: StreamBuilder<Result<List<BookingCustomer>>>(
            stream: _customers,
            builder: (context, customerSnapshot) {
              final customerResult = customerSnapshot.data;
              if (customerResult == null) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (customerResult is FailureResult<List<BookingCustomer>>) {
                return Text(customerResult.failure.message);
              }
              final customers =
                  (customerResult as Success<List<BookingCustomer>>).value;
              return StreamBuilder<Result<List<PhotographyOption>>>(
                stream: _options,
                builder: (context, optionSnapshot) {
                  final optionResult = optionSnapshot.data;
                  if (optionResult == null) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (optionResult is FailureResult<List<PhotographyOption>>) {
                    return Text(optionResult.failure.message);
                  }
                  final options =
                      (optionResult as Success<List<PhotographyOption>>).value;
                  return _form(context, customers, options);
                },
              );
            },
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

  Widget _form(
    BuildContext context,
    List<BookingCustomer> customers,
    List<PhotographyOption> options,
  ) {
    _customerCache = customers;
    _optionCache = options;
    final validCustomerIds = customers.map((customer) => customer.id).toSet();
    final validOptionIds = options.map((option) => option.id).toSet();
    final selectedCustomerId =
        validCustomerIds.contains(_customerId) ? _customerId : null;
    final selectedOptionId =
        validOptionIds.contains(_optionId) ? _optionId : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          initialValue: selectedCustomerId,
          decoration: const InputDecoration(
            labelText: 'عميل الحجز',
            prefixIcon: Icon(Icons.person_outline),
          ),
          items: [
            for (final customer in customers)
              DropdownMenuItem<String>(
                value: customer.id,
                child: Text(
                  '${customer.name} • ${customer.phoneNumber}',
                ),
              ),
          ],
          onChanged: (value) => setState(() => _customerId = value),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: selectedOptionId,
          decoration: const InputDecoration(
            labelText: 'خيار التصوير',
            prefixIcon: Icon(Icons.camera_alt_outlined),
          ),
          items: [
            for (final option in options)
              DropdownMenuItem<String>(
                value: option.id,
                child: Text(
                  '${option.name} • ${option.price.formatted}',
                ),
              ),
          ],
          onChanged: (value) => setState(() => _optionId = value),
        ),
        const SizedBox(height: 10),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule_outlined),
          title: const Text('موعد البداية'),
          subtitle: Text(_formatDateTime(context, _startAt)),
          onTap: _pickStartAt,
        ),
        _field(_location, 'المكان', Icons.location_on_outlined),
        Row(
          children: [
            Expanded(
              child: _field(
                _duration,
                'المدة بالدقائق',
                Icons.timelapse_outlined,
                number: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _field(
                _discount,
                'الخصم',
                Icons.discount_outlined,
                decimal: true,
              ),
            ),
          ],
        ),
        _field(
          _deposit,
          'العربون',
          Icons.payments_outlined,
          decimal: true,
        ),
        _field(_notes, 'ملاحظات', Icons.notes_outlined, maxLines: 2),
        if (_error != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool number = false,
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
                : number
                    ? TextInputType.number
                    : null,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      ),
    );
  }

  Future<void> _pickStartAt() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      initialDate: _startAt,
    );
    if (!mounted || date == null) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startAt),
    );
    if (!mounted || time == null) {
      return;
    }
    setState(() {
      _startAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _save() {
    final customerId = _customerId;
    final optionId = _optionId;
    final duration = int.tryParse(_duration.text.trim());
    final discount = _parseMoney(_discount.text);
    final deposit = _parseMoney(_deposit.text);
    final location = _location.text.trim();
    if (customerId == null ||
        optionId == null ||
        duration == null ||
        duration <= 0 ||
        discount == null ||
        deposit == null ||
        location.isEmpty) {
      setState(() => _error = 'تحقق من العميل والخيارات والوقت والمبالغ.');
      return;
    }

    final customer = _findCustomer(customerId);
    final option = _findOption(optionId);
    if (customer == null || option == null) {
      setState(() => _error = 'تعذر قراءة بيانات الكتالوج.');
      return;
    }

    final totalMinorUnits = option.price.minorUnits - discount.minorUnits;
    if (totalMinorUnits < 0 || deposit.minorUnits > totalMinorUnits) {
      setState(() => _error = 'تحقق من الخصم والعربون مقابل السعر.');
      return;
    }

    try {
      final initial = widget.initial;
      final currency = option.price.currency;
      final now = DateTime.now().toUtc();
      final generatedId = 'booking-${DateTime.now().microsecondsSinceEpoch}';
      Navigator.of(context).pop(
        Booking(
          id: initial?.id ?? generatedId,
          storeId: widget.storeContext.storeId,
          idempotencyKey:
              initial?.idempotencyKey ?? IdempotencyKey(generatedId),
          customerId: customer.id,
          customerName: customer.name,
          customerPhone: customer.phoneNumber,
          customerEmail: customer.email,
          startAt: _startAt,
          durationMinutes: duration,
          location: location,
          notes: _empty(_notes.text),
          photographyOptionId: option.id,
          photographyOptionName: option.name,
          totalPrice: Money(
            minorUnits: totalMinorUnits,
            currency: currency,
          ),
          depositAmount: Money(
            minorUnits: deposit.minorUnits,
            currency: currency,
          ),
          paidAmount: initial?.paidAmount ?? Money.zero(currency: currency),
          status: initial?.status ?? BookingStatus.pending,
          paymentStatus: initial?.paymentStatus ?? BookingPaymentStatus.unpaid,
          payments: initial?.payments ?? const [],
          expenses: initial?.expenses ?? const [],
          totalDiscount: Money(
            minorUnits: discount.minorUnits,
            currency: currency,
          ),
          createdAt: initial?.createdAt ?? now,
          updatedAt: now,
        ),
      );
    } on ArgumentError catch (error) {
      setState(() => _error = error.message?.toString());
    }
  }

  BookingCustomer? _findCustomer(String id) {
    for (final customer in _customerCache) {
      if (customer.id == id) {
        return customer;
      }
    }
    return null;
  }

  PhotographyOption? _findOption(String id) {
    for (final option in _optionCache) {
      if (option.id == id) {
        return option;
      }
    }
    return null;
  }

  String? _empty(String value) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  Money? _parseMoney(String value) {
    final parsed = double.tryParse(value.trim().replaceAll(',', '.'));
    if (parsed == null || parsed.isNaN || parsed.isInfinite || parsed < 0) {
      return null;
    }
    return Money(
      minorUnits: (parsed * 100).round(),
      currency: 'ILS',
    );
  }

  String _formatDateTime(BuildContext context, DateTime value) {
    final local = value.toLocal();
    final date = MaterialLocalizations.of(context).formatMediumDate(local);
    final time = TimeOfDay.fromDateTime(local).format(context);
    return '$date $time';
  }

  @override
  void dispose() {
    _location.dispose();
    _duration.dispose();
    _discount.dispose();
    _deposit.dispose();
    _notes.dispose();
    super.dispose();
  }
}
