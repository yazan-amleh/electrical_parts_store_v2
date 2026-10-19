import 'package:flutter/material.dart';

import '../../../core/money/money.dart';
import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../../payments/domain/repositories/party_payment_repository.dart';
import '../../payments/presentation/party_payments_page.dart';
import '../domain/entities/party.dart';
import '../domain/entities/party_balance.dart';
import '../domain/enums/party_type.dart';
import '../domain/repositories/party_repository.dart';

class PartyDirectoryPage extends StatefulWidget {
  const PartyDirectoryPage({
    required this.repository,
    required this.paymentRepository,
    required this.user,
    required this.membership,
    required this.initialPartyType,
    super.key,
  });

  final PartyRepository? repository;
  final PartyPaymentRepository? paymentRepository;
  final AuthenticatedUser user;
  final StoreMembership membership;
  final PartyType initialPartyType;

  @override
  State<PartyDirectoryPage> createState() => _PartyDirectoryPageState();
}

class _PartyDirectoryPageState extends State<PartyDirectoryPage> {
  final _searchController = TextEditingController();
  late PartyType _partyType;
  List<Party> _parties = const <Party>[];
  Map<String, PartyBalance> _balances = const <String, PartyBalance>{};
  bool _isLoading = true;
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
    _partyType = widget.initialPartyType;
    _loadParties();
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    if (repository == null) {
      return const Center(
        child: Text('مستودع العملاء والموردين غير موصول بهذه البيئة.'),
      );
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return _buildErrorState();
    }

    final search = _searchController.text.trim().toLowerCase();
    final parties = _parties
        .where(
          (party) =>
              search.isEmpty ||
              party.name.toLowerCase().contains(search) ||
              (party.phone?.toLowerCase().contains(search) ?? false) ||
              (party.taxNumber?.toLowerCase().contains(search) ?? false),
        )
        .toList(growable: false);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: parties.isEmpty
                ? const Center(child: Text('لا توجد بيانات مطابقة.'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: parties.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        _buildPartyTile(parties[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final isCustomer = _partyType == PartyType.customer;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  isCustomer
                      ? Icons.people_outline
                      : Icons.local_shipping_outlined,
                  size: 30,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isCustomer ? 'العملاء' : 'الموردون',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _openEditor(),
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة'),
                ),
                IconButton(
                  tooltip: 'تحديث',
                  onPressed: _loadParties,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<PartyType>(
              segments: const [
                ButtonSegment<PartyType>(
                  value: PartyType.customer,
                  icon: Icon(Icons.people_outline),
                  label: Text('عملاء'),
                ),
                ButtonSegment<PartyType>(
                  value: PartyType.supplier,
                  icon: Icon(Icons.local_shipping_outlined),
                  label: Text('موردون'),
                ),
              ],
              selected: {_partyType},
              onSelectionChanged: (selection) {
                setState(() => _partyType = selection.first);
                _loadParties();
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'ابحث بالاسم أو الهاتف أو الرقم الضريبي',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPartyTile(Party party) {
    final balance = _balances[party.id]?.balance ?? Money.zero();
    final isCustomer = party.type == PartyType.customer;
    return Card(
      child: ListTile(
        onTap: () => _openEditor(party),
        leading: CircleAvatar(
          child: Icon(
            isCustomer ? Icons.person_outline : Icons.local_shipping_outlined,
          ),
        ),
        title: Text(party.name),
        subtitle: Text(
          [
            if (party.phone?.isNotEmpty == true) party.phone!,
            if (party.email?.isNotEmpty == true) party.email!,
            party.isActive ? 'نشط' : 'غير نشط',
            'الرصيد: ' + balance.formatted,
          ].join(' • '),
        ),
        trailing: IconButton(
          tooltip: isCustomer ? 'قبض من العميل' : 'دفع للمورد',
          onPressed: () => _openPayment(party),
          icon: Icon(
            isCustomer
                ? Icons.call_received_outlined
                : Icons.call_made_outlined,
          ),
        ),
      ),
    );
  }

  Future<void> _openEditor([Party? initialParty]) async {
    final repository = widget.repository;
    if (repository == null) {
      _showMessage('مستودع العملاء والموردين غير موصول بهذه البيئة.');
      return;
    }
    final party = await showDialog<Party>(
      context: context,
      builder: (_) => _PartyEditorDialog(
        storeId: widget.membership.storeId,
        type: _partyType,
        initialParty: initialParty,
      ),
    );
    if (!mounted || party == null) {
      return;
    }

    final result = await repository.saveParty(
      context: _storeContext,
      party: party,
    );
    if (!mounted) {
      return;
    }
    if (result is FailureResult<void>) {
      _showMessage(result.failure.message);
      return;
    }
    if (result is Success<void>) {
      _showMessage(
        initialParty == null ? 'تمت إضافة البيانات.' : 'تم تحديث البيانات.',
      );
      await _loadParties();
    }
  }

  Future<void> _openPayment(Party party) async {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: SizedBox(
          width: 680,
          child: PartyPaymentsPage(
            repository: widget.paymentRepository,
            user: widget.user,
            membership: widget.membership,
            initialPartyType: party.type,
            initialPartyId: party.id,
          ),
        ),
      ),
    );
    if (mounted) {
      await _loadParties();
    }
  }

  Future<void> _loadParties() async {
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
    final partiesResult = await repository.getParties(
      context: _storeContext,
      type: _partyType,
    );
    if (!mounted) {
      return;
    }
    if (partiesResult is FailureResult<List<Party>>) {
      setState(() {
        _isLoading = false;
        _errorMessage = partiesResult.failure.message;
      });
      return;
    }
    final balancesResult = await repository.getBalances(
      context: _storeContext,
      type: _partyType,
    );
    if (!mounted) {
      return;
    }
    if (balancesResult is FailureResult<Map<String, PartyBalance>>) {
      setState(() {
        _isLoading = false;
        _errorMessage = balancesResult.failure.message;
      });
      return;
    }
    setState(() {
      _isLoading = false;
      _parties = (partiesResult as Success<List<Party>>).value;
      _balances = (balancesResult as Success<Map<String, PartyBalance>>).value;
    });
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
            onPressed: _loadParties,
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
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

class _PartyEditorDialog extends StatefulWidget {
  const _PartyEditorDialog({
    required this.storeId,
    required this.type,
    this.initialParty,
  });

  final String storeId;
  final PartyType type;
  final Party? initialParty;

  @override
  State<_PartyEditorDialog> createState() => _PartyEditorDialogState();
}

class _PartyEditorDialogState extends State<_PartyEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  late final TextEditingController _taxNumberController;
  late final TextEditingController _creditLimitController;
  late final TextEditingController _notesController;
  late bool _isActive;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final party = widget.initialParty;
    _nameController = TextEditingController(text: party?.name ?? '');
    _phoneController = TextEditingController(text: party?.phone ?? '');
    _emailController = TextEditingController(text: party?.email ?? '');
    _addressController = TextEditingController(text: party?.address ?? '');
    _taxNumberController = TextEditingController(text: party?.taxNumber ?? '');
    _creditLimitController = TextEditingController(
      text: party?.creditLimit.formatted.split(' ').first ?? '0',
    );
    _notesController = TextEditingController(text: party?.notes ?? '');
    _isActive = party?.isActive ?? true;
  }

  @override
  Widget build(BuildContext context) {
    final isCustomer = widget.type == PartyType.customer;
    return AlertDialog(
      title: Text(
        widget.initialParty == null
            ? (isCustomer ? 'إضافة عميل' : 'إضافة مورد')
            : (isCustomer ? 'تعديل عميل' : 'تعديل مورد'),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(_nameController, 'الاسم', Icons.person_outline),
              _field(_phoneController, 'الهاتف', Icons.phone_outlined),
              _field(
                  _emailController, 'البريد الإلكتروني', Icons.email_outlined),
              _field(
                _addressController,
                'العنوان',
                Icons.location_on_outlined,
                maxLines: 2,
              ),
              _field(
                _taxNumberController,
                'الرقم الضريبي',
                Icons.numbers_outlined,
              ),
              _field(
                _creditLimitController,
                'حد الائتمان',
                Icons.credit_score_outlined,
                decimal: true,
              ),
              _field(
                _notesController,
                'ملاحظات',
                Icons.notes_outlined,
                maxLines: 2,
              ),
              SwitchListTile(
                value: _isActive,
                title: const Text('البيان نشط'),
                onChanged: (value) => setState(() => _isActive = value),
              ),
              if (_errorMessage != null)
                Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
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
        keyboardType: decimal
            ? const TextInputType.numberWithOptions(decimal: true)
            : null,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
        ),
      ),
    );
  }

  Money? _parseMoney(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      return Money.zero();
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

  void _save() {
    final name = _nameController.text.trim();
    final creditLimit = _parseMoney(_creditLimitController.text);
    if (name.isEmpty || creditLimit == null || creditLimit.isNegative) {
      setState(() => _errorMessage = 'تحقق من الاسم وحد الائتمان.');
      return;
    }
    try {
      final existing = widget.initialParty;
      final party = Party(
        id: existing?.id ??
            ['party-', DateTime.now().microsecondsSinceEpoch].join(),
        storeId: widget.storeId,
        type: widget.type,
        name: name,
        phone: _empty(_phoneController.text),
        email: _empty(_emailController.text),
        address: _empty(_addressController.text),
        taxNumber: _empty(_taxNumberController.text),
        notes: _empty(_notesController.text),
        creditLimit: creditLimit,
        isActive: _isActive,
      );
      Navigator.of(context).pop(party);
    } on ArgumentError catch (error) {
      setState(() => _errorMessage = error.message.toString());
    }
  }

  String? _empty(String value) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _taxNumberController.dispose();
    _creditLimitController.dispose();
    _notesController.dispose();
    super.dispose();
  }
}
