import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/errors/failure.dart';
import '../../../core/idempotency/idempotency_key.dart';
import '../../../core/money/money.dart';
import '../../../core/result/result.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../../auth/domain/enums/store_role.dart';
import '../domain/entities/expense.dart';
import '../domain/entities/expense_posting_plan.dart';
import '../domain/enums/expense_payment_method.dart';
import '../domain/repositories/expense_repository.dart';

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({
    required this.repository,
    required this.user,
    required this.membership,
    super.key,
  });

  final ExpenseRepository? repository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  static const _currency = 'ILS';
  static const _cashAccountId = '1110';
  static const _bankAccountId = '1121';
  static const _cardAccountId = '1121';
  static const _supplierPayableAccountId = '2110';
  static const _inputTaxAccountId = '1170';

  static const _expenseAccounts = <String, String>{
    '6110': 'الإيجارات',
    '6120': 'الرواتب والأجور',
    '6130': 'المرافق والخدمات',
  };

  final _amountController = TextEditingController();
  final _taxController = TextEditingController();
  final _supplierController = TextEditingController();
  final _descriptionController = TextEditingController();

  ExpensePaymentMethod _paymentMethod = ExpensePaymentMethod.cash;
  String _expenseAccountId = '6130';
  bool _isPosting = false;
  Expense? _pendingExpense;
  String? _pendingSignature;
  bool _pendingQueued = false;
  bool _pendingUncertain = false;

  Money get _amount =>
      _parseMoney(_amountController.text) ?? Money.zero(currency: _currency);

  Money get _tax =>
      _parseMoney(_taxController.text) ?? Money.zero(currency: _currency);

  Money get _total => _amount + _tax;

  @override
  void didUpdateWidget(covariant ExpensesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.id != widget.user.id ||
        oldWidget.membership.storeId != widget.membership.storeId) {
      _pendingExpense = null;
      _pendingSignature = null;
      _pendingQueued = false;
      _pendingUncertain = false;
      _clearForm();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.membership.role.canPostAccounting) {
      return const Center(
        child: Text('ليس لديك صلاحية لترحيل المصروفات.'),
      );
    }
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
                child: Form(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.receipt_long_outlined, size: 30),
                          const SizedBox(width: 10),
                          Text(
                            'تسجيل مصروف',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'سيُنشأ القيد وتُحدّث الذمم أو الصندوق ضمن عملية ذرية واحدة.',
                      ),
                      const SizedBox(height: 24),
                      DropdownButtonFormField<String>(
                        value: _expenseAccountId,
                        decoration: const InputDecoration(
                          labelText: 'حساب المصروف',
                          prefixIcon: Icon(Icons.account_tree_outlined),
                        ),
                        items: _expenseAccounts.entries
                            .map(
                              (entry) => DropdownMenuItem<String>(
                                value: entry.key,
                                child: Text('${entry.key} — ${entry.value}'),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: _isPosting
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _expenseAccountId = value);
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _amountController,
                        enabled: !_isPosting,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'المبلغ قبل الضريبة',
                          hintText: '0.00',
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _taxController,
                        enabled: !_isPosting,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'ضريبة المدخلات',
                          hintText: '0.00',
                          prefixIcon: Icon(Icons.percent_outlined),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<ExpensePaymentMethod>(
                        value: _paymentMethod,
                        decoration: const InputDecoration(
                          labelText: 'طريقة الدفع',
                          prefixIcon: Icon(
                            Icons.account_balance_wallet_outlined,
                          ),
                        ),
                        items: ExpensePaymentMethod.values
                            .map(
                              (method) =>
                                  DropdownMenuItem<ExpensePaymentMethod>(
                                value: method,
                                child: Text(method.arabicLabel),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: _isPosting
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _paymentMethod = value);
                                }
                              },
                      ),
                      if (_paymentMethod == ExpensePaymentMethod.credit)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: TextField(
                            controller: _supplierController,
                            enabled: !_isPosting,
                            decoration: const InputDecoration(
                              labelText: 'معرّف المورد',
                              hintText: 'أدخل supplierId',
                              prefixIcon: Icon(Icons.local_shipping_outlined),
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _descriptionController,
                        enabled: !_isPosting,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'الوصف',
                          hintText: 'مثال: فاتورة كهرباء شهرية',
                          prefixIcon: Icon(Icons.notes_outlined),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Text('الإجمالي'),
                            const Spacer(),
                            Text(
                              _total.formatted,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_pendingQueued || _pendingUncertain) ...[
                        const SizedBox(height: 12),
                        MaterialBanner(
                          content: Text(
                            _pendingQueued
                                ? 'هذا المصروف محفوظ في طابور التنفيذ. '
                                    'لا تنشئ مصروفًا آخر حتى تُحسم النتيجة.'
                                : 'تعذر التأكد من نتيجة الترحيل السابقة. '
                                    'أعد نفس المصروف بنفس البيانات فقط.',
                          ),
                          actions: const <Widget>[],
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _isPosting ? null : _postExpense,
                        icon: _isPosting
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline),
                        label: Text(
                          _isPosting ? 'جارٍ الترحيل...' : 'ترحيل المصروف',
                        ),
                      ),
                    ],
                  ),
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
    return Money(minorUnits: major * 100 + fraction, currency: _currency);
  }

  Future<void> _postExpense() async {
    if (_isPosting) {
      return;
    }
    if (_pendingQueued) {
      _showMessage(
        'هذا المصروف محفوظ في طابور التنفيذ. لا تُرسله مرة أخرى '
        'حتى يتم التحقق من نتيجته.',
      );
      return;
    }

    final repository = widget.repository;
    if (repository == null) {
      _showMessage('مستودع المصروفات غير موصول بهذه البيئة.');
      return;
    }

    final amount = _parseMoney(_amountController.text);
    final tax = _parseMoney(_taxController.text);
    if (amount == null || amount.isZero) {
      _showMessage('أدخل مبلغاً صحيحاً أكبر من صفر.');
      return;
    }
    if (tax == null) {
      _showMessage('قيمة الضريبة غير صحيحة.');
      return;
    }

    final supplierId = _supplierController.text.trim();
    if (_paymentMethod == ExpensePaymentMethod.credit && supplierId.isEmpty) {
      _showMessage('المصروف الآجل يحتاج معرّف المورد.');
      return;
    }

    final description = _descriptionController.text.trim();
    final signature = jsonEncode([
      widget.membership.storeId,
      widget.user.id,
      _paymentMethod.name,
      _expenseAccountId,
      amount.minorUnits,
      amount.currency,
      tax.minorUnits,
      tax.currency,
      _paymentMethod == ExpensePaymentMethod.credit ? supplierId : null,
      description,
    ]);
    if (_pendingUncertain && _pendingSignature != signature) {
      _showMessage(
        'نتيجة المصروف السابق غير محسومة. أعد نفس المصروف بنفس البيانات '
        'ولا تنشئ مصروفًا جديدًا حتى يتم تأكيد النتيجة.',
      );
      return;
    }

    final previous = _pendingSignature == signature ? _pendingExpense : null;
    final expenseId =
        previous?.id ?? 'expense-${DateTime.now().microsecondsSinceEpoch}';
    final expense = previous ??
        Expense(
          id: expenseId,
          storeId: widget.membership.storeId,
          idempotencyKey: IdempotencyKey(expenseId),
          postedAt: DateTime.now().toUtc(),
          paymentMethod: _paymentMethod,
          expenseAccountId: _expenseAccountId,
          amount: amount,
          tax: tax,
          supplierId:
              _paymentMethod == ExpensePaymentMethod.credit ? supplierId : null,
          description: description.isEmpty ? null : description,
        );

    _pendingSignature = signature;
    _pendingExpense = expense;

    setState(() => _isPosting = true);
    final result = await repository.postExpense(
      context: expense.contextFor(widget.user.id),
      expense: expense,
      accounts: _postingAccounts,
    );
    if (!mounted) {
      return;
    }
    setState(() => _isPosting = false);

    if (result is FailureResult<ExpensePostingPlan>) {
      final failure = result.failure;
      if (failure is QueuedFailure) {
        _pendingQueued = true;
        _pendingUncertain = false;
        _showMessage(
          'تم حفظ المصروف للطابور. لا تُنشئ مصروفًا آخر حتى تُحسم النتيجة.',
        );
      } else if (failure is InfrastructureFailure) {
        _pendingUncertain = true;
        _showMessage(
          'تعذر التأكد من نتيجة الترحيل. أعد نفس المصروف بنفس البيانات فقط.',
        );
      } else {
        _pendingExpense = null;
        _pendingSignature = null;
        _pendingQueued = false;
        _pendingUncertain = false;
        _showMessage(failure.message);
      }
      return;
    }

    if (result is Success<ExpensePostingPlan>) {
      _pendingExpense = null;
      _pendingSignature = null;
      _pendingQueued = false;
      _pendingUncertain = false;
      _clearForm();
      _showMessage('تم ترحيل المصروف والقيد بنجاح.');
    }
  }

  ExpensePostingAccounts get _postingAccounts {
    String? settlementAccountId;
    switch (_paymentMethod) {
      case ExpensePaymentMethod.cash:
        settlementAccountId = _cashAccountId;
      case ExpensePaymentMethod.bank:
        settlementAccountId = _bankAccountId;
      case ExpensePaymentMethod.card:
        settlementAccountId = _cardAccountId;
      case ExpensePaymentMethod.credit:
        settlementAccountId = null;
    }

    return ExpensePostingAccounts(
      settlementAccountId: settlementAccountId,
      supplierPayableAccountId: _supplierPayableAccountId,
      inputTaxAccountId: _inputTaxAccountId,
    );
  }

  void _clearForm() {
    setState(() {
      _amountController.clear();
      _taxController.clear();
      _supplierController.clear();
      _descriptionController.clear();
      _paymentMethod = ExpensePaymentMethod.cash;
      _expenseAccountId = '6130';
    });
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
    _amountController.dispose();
    _taxController.dispose();
    _supplierController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}

extension on ExpensePaymentMethod {
  String get arabicLabel {
    switch (this) {
      case ExpensePaymentMethod.cash:
        return 'نقدي';
      case ExpensePaymentMethod.bank:
        return 'بنك';
      case ExpensePaymentMethod.card:
        return 'بطاقة';
      case ExpensePaymentMethod.credit:
        return 'آجل';
    }
  }
}
