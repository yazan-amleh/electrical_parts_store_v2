import 'package:flutter/material.dart';

import '../../../core/errors/failure.dart';
import '../../../core/idempotency/idempotency_key.dart';
import '../../../core/money/money.dart';
import '../../../core/result/result.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../../parties/domain/enums/party_type.dart';
import '../domain/entities/party_payment.dart';
import '../domain/entities/party_payment_posting_plan.dart';
import '../domain/enums/party_payment_method.dart';
import '../domain/repositories/party_payment_repository.dart';

class PartyPaymentsPage extends StatefulWidget {
  const PartyPaymentsPage({
    required this.repository,
    required this.user,
    required this.membership,
    this.initialPartyType = PartyType.customer,
    this.initialPartyId,
    super.key,
  });

  final PartyPaymentRepository? repository;
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
  static const _cardReceivableAccountId = '1160';
  static const _customerReceivableAccountId = '1140';
  static const _supplierPayableAccountId = '2110';

  final _partyController = TextEditingController();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  late PartyType _partyType;
  PartyPaymentMethod _paymentMethod = PartyPaymentMethod.cash;
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    _partyType = widget.initialPartyType;
    if (widget.initialPartyId != null) {
      _partyController.text = widget.initialPartyId!;
    }
  }

  @override
  Widget build(BuildContext context) {
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
                              setState(() => _partyType = selection.first);
                            },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _partyController,
                      enabled: !_isPosting,
                      decoration: InputDecoration(
                        labelText: isCustomer ? 'معرّف العميل' : 'معرّف المورد',
                        hintText:
                            isCustomer ? 'أدخل customerId' : 'أدخل supplierId',
                        prefixIcon: Icon(
                          isCustomer
                              ? Icons.person_outline
                              : Icons.local_shipping_outlined,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
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
                      initialValue: _paymentMethod,
                      decoration: const InputDecoration(
                        labelText: 'طريقة الدفع',
                        prefixIcon: Icon(
                          Icons.account_balance_wallet_outlined,
                        ),
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
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _isPosting ? null : _postPayment,
                      icon: _isPosting
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: Text(
                        _isPosting ? 'جارٍ الترحيل...' : actionLabel,
                      ),
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
    return Money(
      minorUnits: major * 100 + fraction,
      currency: _currency,
    );
  }

  Future<void> _postPayment() async {
    final repository = widget.repository;
    if (repository == null) {
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

    final paymentId = 'party-payment-${DateTime.now().microsecondsSinceEpoch}';
    final payment = PartyPayment(
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
    );

    setState(() => _isPosting = true);
    final result = await repository.postPartyPayment(
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
        _showMessage('تم حفظ الحركة للطابور وسيُرحّل عند عودة الاتصال.');
      } else {
        _showMessage(failure.message);
      }
      return;
    }

    if (result is Success<PartyPaymentPostingPlan>) {
      _amountController.clear();
      _descriptionController.clear();
      _showMessage('تم ترحيل الحركة والقيد وكشف الحساب بنجاح.');
    }
  }

  String get _partyAccountId {
    return _partyType == PartyType.customer
        ? _customerReceivableAccountId
        : _supplierPayableAccountId;
  }

  String get _settlementAccountId {
    if (_paymentMethod == PartyPaymentMethod.card &&
        _partyType == PartyType.customer) {
      return _cardReceivableAccountId;
    }
    return _paymentMethod == PartyPaymentMethod.cash
        ? _cashAccountId
        : _bankAccountId;
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
    }
  }
}
