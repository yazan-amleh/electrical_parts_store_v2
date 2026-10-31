import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/errors/failure.dart';
import '../../../core/idempotency/idempotency_key.dart';
import '../../../core/money/money.dart';
import '../../../core/result/result.dart';
import '../../../core/tenancy/store_context.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../../auth/domain/enums/store_role.dart';
import '../../parties/domain/entities/party.dart';
import '../../parties/domain/enums/party_type.dart';
import '../../parties/domain/repositories/party_repository.dart';
import '../domain/entities/party_payment.dart';
import '../domain/entities/party_payment_posting_plan.dart';
import '../domain/enums/party_payment_method.dart';
import '../domain/repositories/party_payment_repository.dart';
import '../domain/repositories/voucher_draft_repository.dart';

class PartyPaymentsPage extends StatefulWidget {
  const PartyPaymentsPage({
    required this.repository,
    this.draftRepository,
    this.partyRepository,
    required this.user,
    required this.membership,
    this.initialPartyType = PartyType.customer,
    this.initialPartyId,
    super.key,
  });

  final PartyPaymentRepository? repository;
  final VoucherDraftRepository? draftRepository;
  final PartyRepository? partyRepository;
  final AuthenticatedUser user;
  final StoreMembership membership;
  final PartyType initialPartyType;
  final String? initialPartyId;

  @override
  State<PartyPaymentsPage> createState() => _PartyPaymentsPageState();
}

class _PartyPaymentsPageState extends State<PartyPaymentsPage> {
  static const _currency = 'ILS';
  static const _cashAccountId = '1110';
  static const _bankAccountId = '1121';
  static const _checksAccountId = '1130';
  static const _issuedChecksAccountId = '2210';
  static const _cardReceivableAccountId = '1160';
  static const _customerReceivableAccountId = '1140';
  static const _supplierPayableAccountId = '2110';

  final _partyController = TextEditingController();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _chequeNumberController = TextEditingController();
  final _bankNameController = TextEditingController();

  late PartyType _partyType;
  PartyPaymentMethod _paymentMethod = PartyPaymentMethod.cash;
  DateTime? _dueDate;
  bool _isPosting = false;
  PartyPayment? _pendingPayment;
  String? _pendingSignature;
  bool _pendingQueued = false;
  bool _pendingUncertain = false;
  List<Party> _parties = const <Party>[];
  Party? _selectedParty;
  bool _isLoadingParties = false;
  String? _partyLoadError;
  int _partyLoadEpoch = 0;

  StoreContext get _storeContext => StoreContext(
        storeId: widget.membership.storeId,
        userId: widget.user.id,
      );

  @override
  void initState() {
    super.initState();
    _partyType = widget.initialPartyType;
    if (widget.initialPartyId != null) {
      _partyController.text = widget.initialPartyId!;
    }
    _loadParties();
  }

  @override
  void didUpdateWidget(covariant PartyPaymentsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.id != widget.user.id ||
        oldWidget.membership.storeId != widget.membership.storeId ||
        oldWidget.initialPartyType != widget.initialPartyType ||
        oldWidget.initialPartyId != widget.initialPartyId) {
      _partyType = widget.initialPartyType;
      _partyController.text = widget.initialPartyId ?? '';
      _selectedParty = null;
      _parties = const <Party>[];
      _pendingPayment = null;
      _pendingSignature = null;
      _pendingQueued = false;
      _pendingUncertain = false;
      _amountController.clear();
      _descriptionController.clear();
      _chequeNumberController.clear();
      _bankNameController.clear();
      _dueDate = null;
      _paymentMethod = PartyPaymentMethod.cash;
      _loadParties();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.membership.role.canPostAccounting) {
      return const Center(
        child: Text('ليس لديك صلاحية لترحيل سندات القبض أو الدفع.'),
      );
    }
    final isCustomer = _partyType == PartyType.customer;
    final actionLabel = isCustomer ? 'قبض من عميل' : 'دفع لمورد';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isCustomer
                              ? Icons.call_received_outlined
                              : Icons.call_made_outlined,
                          size: 30,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          actionLabel,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isCustomer
                          ? 'يُخفض رصيد العميل ويزيد الصندوق أو البنك ضمن قيد ذري.'
                          : 'يُخفض رصيد المورد ويُنقص الصندوق أو البنك ضمن قيد ذري.',
                    ),
                    const SizedBox(height: 24),
                    SegmentedButton<PartyType>(
                      segments: const [
                        ButtonSegment<PartyType>(
                          value: PartyType.customer,
                          icon: Icon(Icons.people_outline),
                          label: Text('عميل'),
                        ),
                        ButtonSegment<PartyType>(
                          value: PartyType.supplier,
                          icon: Icon(Icons.local_shipping_outlined),
                          label: Text('مورد'),
                        ),
                      ],
                      selected: {_partyType},
                      onSelectionChanged: _isPosting
                          ? null
                          : (selection) {
                              final nextType = selection.first;
                              if (nextType == _partyType) {
                                return;
                              }
                              setState(() {
                                _partyType = nextType;
                                _selectedParty = null;
                                _partyController.clear();
                                _partyLoadError = null;
                              });
                              _loadParties();
                            },
                    ),
                    const SizedBox(height: 16),
                    _buildPartySelector(isCustomer),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('party-payment-amount'),
                      controller: _amountController,
                      enabled: !_isPosting,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'المبلغ',
                        hintText: '0.00',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<PartyPaymentMethod>(
                      value: _paymentMethod,
                      decoration: const InputDecoration(
                        labelText: 'طريقة الدفع',
                        prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                      ),
                      items: PartyPaymentMethod.values
                          .map(
                            (method) => DropdownMenuItem<PartyPaymentMethod>(
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
                    if (_paymentMethod == PartyPaymentMethod.card)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'للقبض بالبطاقة سيُستخدم حساب ذمم البطاقات 1160.',
                        ),
                      ),
                    if (_paymentMethod == PartyPaymentMethod.cheque) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          isCustomer
                              ? 'يُسجّل الشيك الوارد في حساب الشيكات قيد التحصيل '
                                  '1130، ولا يزيد الصندوق حتى يتم تحصيله.'
                              : 'يُسجّل الشيك الصادر في حساب الشيكات الصادرة '
                                  '2210، ولا ينقص البنك حتى يتم صرفه.',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _chequeNumberController,
                        enabled: !_isPosting,
                        decoration: const InputDecoration(
                          labelText: 'رقم الشيك',
                          prefixIcon: Icon(Icons.numbers_outlined),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _bankNameController,
                        enabled: !_isPosting,
                        decoration: const InputDecoration(
                          labelText: 'البنك المسحوب عليه',
                          prefixIcon: Icon(Icons.account_balance_outlined),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _isPosting ? null : _pickDueDate,
                        icon: const Icon(Icons.event_outlined),
                        label: Text(
                          _dueDate == null
                              ? 'اختيار تاريخ الاستحقاق (اختياري)'
                              : 'الاستحقاق: ${_formatDate(_dueDate!)}',
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descriptionController,
                      enabled: !_isPosting,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'الوصف',
                        hintText: 'مثال: دفعة على الحساب',
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                    ),
                    if (_pendingQueued || _pendingUncertain) ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _pendingQueued
                                ? 'هذه الحركة محفوظة في طابور التنفيذ. '
                                    'لا تنشئ حركة أخرى حتى يتم التحقق من نتيجتها.'
                                : 'تعذر التأكد من نتيجة الترحيل السابقة. '
                                    'أعد نفس الحركة بنفس البيانات فقط.',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 20),
                    if (widget.draftRepository != null) ...[
                      OutlinedButton.icon(
                        onPressed: _isPosting
                            ? null
                            : () => _postPayment(saveDraft: true),
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('حفظ كمسودة دون ترحيل'),
                      ),
                      const SizedBox(height: 10),
                    ],
                    FilledButton.icon(
                      key: const ValueKey('party-payment-submit'),
                      onPressed: _isPosting ? null : _postPayment,
                      icon: _isPosting
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: Text(_isPosting ? 'جارٍ الترحيل...' : actionLabel),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPartySelector(bool isCustomer) {
    final repository = widget.partyRepository;
    if (repository == null) {
      return TextField(
        controller: _partyController,
        enabled: !_isPosting,
        decoration: InputDecoration(
          labelText: isCustomer ? 'معرّف العميل' : 'معرّف المورد',
          hintText: isCustomer ? 'أدخل customerId' : 'أدخل supplierId',
          prefixIcon: Icon(
            isCustomer ? Icons.person_outline : Icons.local_shipping_outlined,
          ),
        ),
      );
    }

    if (_isLoadingParties) {
      return const LinearProgressIndicator();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Autocomplete<Party>(
          key: ValueKey(
            'party-selector-${_partyType.name}-'
            '$_partyLoadEpoch-${_selectedParty?.id ?? 'none'}',
          ),
          initialValue: TextEditingValue(
            text: _selectedParty?.name ?? '',
          ),
          displayStringForOption: (party) => party.name,
          optionsBuilder: (textEditingValue) {
            final query = textEditingValue.text.trim().toLowerCase();
            final candidates = query.isEmpty
                ? _parties
                : _parties.where((party) {
                    return party.name.toLowerCase().contains(query) ||
                        party.id.toLowerCase().contains(query) ||
                        (party.phone?.toLowerCase().contains(query) ?? false);
                  }).toList(growable: false);
            return candidates.take(20);
          },
          onSelected: (party) {
            setState(() {
              _selectedParty = party;
              _partyController.text = party.id;
              _partyLoadError = null;
            });
          },
          fieldViewBuilder: (
            context,
            textEditingController,
            focusNode,
            onFieldSubmitted,
          ) {
            return TextField(
              key: const ValueKey('party-payment-party-search'),
              controller: textEditingController,
              focusNode: focusNode,
              enabled: !_isPosting,
              decoration: InputDecoration(
                labelText: isCustomer ? 'العميل' : 'المورد',
                hintText: isCustomer
                    ? 'ابحث بالاسم أو المعرّف أو الهاتف'
                    : 'ابحث باسم المورد أو المعرّف أو الهاتف',
                prefixIcon: Icon(
                  isCustomer
                      ? Icons.person_search_outlined
                      : Icons.manage_search_outlined,
                ),
                suffixIcon: _selectedParty == null
                    ? null
                    : IconButton(
                        tooltip: 'إلغاء الاختيار',
                        onPressed: _isPosting
                            ? null
                            : () {
                                setState(() {
                                  _selectedParty = null;
                                  _partyController.clear();
                                  _partyLoadEpoch++;
                                });
                              },
                        icon: const Icon(Icons.clear),
                      ),
              ),
              onChanged: (_) {
                if (_selectedParty != null) {
                  _selectedParty = null;
                  _partyController.clear();
                }
              },
              onSubmitted: (_) => onFieldSubmitted(),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final rows = options.toList(growable: false);
            return Align(
              alignment: Alignment.topRight,
              child: Material(
                elevation: 8,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 620,
                    maxHeight: 280,
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final party = rows[index];
                      final details = [
                        party.id,
                        if (party.phone?.trim().isNotEmpty == true)
                          party.phone!.trim(),
                      ].join(' • ');
                      return ListTile(
                        title: Text(party.name),
                        subtitle: Text(details),
                        onTap: () => onSelected(party),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
        if (_partyLoadError != null) ...[
          const SizedBox(height: 6),
          Text(
            _partyLoadError!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _isPosting ? null : _loadParties,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة تحميل القائمة'),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _loadParties() async {
    final repository = widget.partyRepository;
    if (repository == null) {
      return;
    }
    final epoch = ++_partyLoadEpoch;
    final requestedStore = widget.membership.storeId;
    final requestedUser = widget.user.id;
    setState(() {
      _isLoadingParties = true;
      _partyLoadError = null;
    });

    final result = await repository.getParties(
      context: _storeContext,
      type: _partyType,
    );
    if (!mounted ||
        epoch != _partyLoadEpoch ||
        requestedStore != widget.membership.storeId ||
        requestedUser != widget.user.id) {
      return;
    }
    if (result is FailureResult<List<Party>>) {
      setState(() {
        _isLoadingParties = false;
        _parties = const <Party>[];
        _partyLoadError = result.failure.message;
      });
      return;
    }

    final parties = (result as Success<List<Party>>).value;
    Party? selected;
    final requestedId = _partyController.text.trim();
    if (requestedId.isNotEmpty) {
      for (final party in parties) {
        if (party.id == requestedId) {
          selected = party;
          break;
        }
      }
    }
    setState(() {
      _isLoadingParties = false;
      _parties = parties;
      _selectedParty = selected;
      if (requestedId.isNotEmpty && selected == null) {
        _partyController.clear();
        _partyLoadError = 'الطرف المحدد غير موجود أو غير نشط في المتجر الحالي.';
      }
    });
  }

  Money? _parseMoney(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      return Money.zero(currency: _currency);
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
    return Money(minorUnits: major * 100 + fraction, currency: _currency);
  }

  Future<void> _postPayment({bool saveDraft = false}) async {
    if (_isPosting) return;
    if (_pendingQueued) {
      _showMessage(
        'هذه الحركة محفوظة في طابور الترحيل. لا تُرسلها مرة أخرى '
        'حتى يتم التحقق من نتيجتها.',
      );
      return;
    }
    final repository = widget.repository;
    if (!saveDraft && repository == null) {
      _showMessage('مستودع المقبوضات والمدفوعات غير موصول بهذه البيئة.');
      return;
    }

    final partyId = _partyController.text.trim();
    if (partyId.isEmpty) {
      _showMessage(
        _partyType == PartyType.customer
            ? 'أدخل معرّف العميل.'
            : 'أدخل معرّف المورد.',
      );
      return;
    }

    final amount = _parseMoney(_amountController.text);
    if (amount == null || amount.isZero) {
      _showMessage('أدخل مبلغاً صحيحاً أكبر من صفر.');
      return;
    }

    final chequeNumber = _paymentMethod == PartyPaymentMethod.cheque
        ? _chequeNumberController.text.trim()
        : null;
    final bankName = _paymentMethod == PartyPaymentMethod.cheque
        ? _bankNameController.text.trim()
        : null;
    if (_paymentMethod == PartyPaymentMethod.cheque &&
        (chequeNumber == null ||
            chequeNumber.isEmpty ||
            bankName == null ||
            bankName.isEmpty)) {
      _showMessage('أدخل رقم الشيك واسم البنك.');
      return;
    }

    final signature = jsonEncode([
      widget.membership.storeId,
      widget.user.id,
      _partyType.name,
      partyId,
      amount.minorUnits,
      amount.currency,
      _paymentMethod.name,
      _descriptionController.text.trim(),
      chequeNumber,
      bankName,
      _dueDate?.toUtc().toIso8601String(),
    ]);
    if (_pendingUncertain && _pendingSignature != signature) {
      _showMessage(
        'نتيجة الحركة السابقة غير محسومة. أعد نفس الحركة بنفس البيانات '
        'ولا تنشئ حركة جديدة حتى يتم تأكيد النتيجة.',
      );
      return;
    }

    final previous = _pendingSignature == signature ? _pendingPayment : null;
    final paymentId = previous?.id ??
        'party-payment-${DateTime.now().microsecondsSinceEpoch}';
    final payment = previous ??
        PartyPayment(
          id: paymentId,
          storeId: widget.membership.storeId,
          idempotencyKey: IdempotencyKey(paymentId),
          postedAt: DateTime.now().toUtc(),
          partyType: _partyType,
          partyId: partyId,
          paymentMethod: _paymentMethod,
          amount: amount,
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          chequeNumber: chequeNumber,
          bankName: bankName,
          dueDate: _dueDate,
        );

    _pendingSignature = signature;
    _pendingPayment = payment;

    if (saveDraft) {
      final draftRepository = widget.draftRepository;
      if (draftRepository == null) return;
      setState(() => _isPosting = true);
      final draftResult = await draftRepository.saveDraft(
        context: payment.contextFor(widget.user.id),
        payment: payment,
        accounts: PartyPaymentPostingAccounts(
          settlementAccountId: _settlementAccountId,
          partyAccountId: _partyAccountId,
        ),
      );
      if (!mounted) return;
      setState(() => _isPosting = false);
      if (draftResult is FailureResult<String>) {
        _showMessage(draftResult.failure.message);
      } else {
        _pendingPayment = null;
        _pendingSignature = null;
        _showMessage(
            'تم حفظ المسودة دون ترحيل. أرسلها للاعتماد من تبويب المسودات.');
        _amountController.clear();
        _descriptionController.clear();
        _chequeNumberController.clear();
        _bankNameController.clear();
      }
      return;
    }

    setState(() => _isPosting = true);
    final result = await repository!.postPartyPayment(
      context: payment.contextFor(widget.user.id),
      payment: payment,
      accounts: PartyPaymentPostingAccounts(
        settlementAccountId: _settlementAccountId,
        partyAccountId: _partyAccountId,
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() => _isPosting = false);

    if (result is FailureResult<PartyPaymentPostingPlan>) {
      final failure = result.failure;
      if (failure is QueuedFailure) {
        _pendingQueued = true;
        _pendingUncertain = false;
        _showMessage(
          'تم حفظ الحركة للطابور. لا تعِد إرسالها قبل التحقق من حالتها.',
        );
      } else if (failure is InfrastructureFailure) {
        _pendingUncertain = true;
        _showMessage(
          'تعذر التأكد من نتيجة الترحيل. أعد نفس الحركة بنفس البيانات فقط.',
        );
      } else {
        _pendingPayment = null;
        _pendingSignature = null;
        _pendingQueued = false;
        _pendingUncertain = false;
        _showMessage(failure.message);
      }
      return;
    }

    if (result is Success<PartyPaymentPostingPlan>) {
      _pendingPayment = null;
      _pendingSignature = null;
      _pendingQueued = false;
      _pendingUncertain = false;
      _amountController.clear();
      _descriptionController.clear();
      _chequeNumberController.clear();
      _bankNameController.clear();
      setState(() => _dueDate = null);
      _showMessage('تم ترحيل الحركة والقيد وكشف الحساب بنجاح.');
    }
  }

  String get _partyAccountId {
    return _partyType == PartyType.customer
        ? _customerReceivableAccountId
        : _supplierPayableAccountId;
  }

  String get _settlementAccountId {
    if (_paymentMethod == PartyPaymentMethod.cheque) {
      return _partyType == PartyType.customer
          ? _checksAccountId
          : _issuedChecksAccountId;
    }
    if (_paymentMethod == PartyPaymentMethod.card &&
        _partyType == PartyType.customer) {
      return _cardReceivableAccountId;
    }
    return _paymentMethod == PartyPaymentMethod.cash
        ? _cashAccountId
        : _bankAccountId;
  }

  Future<void> _pickDueDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected != null && mounted) {
      setState(() => _dueDate = selected);
    }
  }

  String _formatDate(DateTime value) {
    return value.toLocal().toIso8601String().split('T').first;
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
    _partyController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    _chequeNumberController.dispose();
    _bankNameController.dispose();
    super.dispose();
  }
}

extension on PartyPaymentMethod {
  String get arabicLabel {
    switch (this) {
      case PartyPaymentMethod.cash:
        return 'نقدي';
      case PartyPaymentMethod.bank:
        return 'بنك';
      case PartyPaymentMethod.card:
        return 'بطاقة';
      case PartyPaymentMethod.cheque:
        return 'شيك';
    }
  }
}
