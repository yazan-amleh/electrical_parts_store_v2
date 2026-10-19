import 'package:flutter/material.dart';

import '../../../core/errors/failure.dart';
import '../../../core/idempotency/idempotency_key.dart';
import '../../../core/money/money.dart';
import '../../../core/result/result.dart';
import '../../auth/domain/entities/authenticated_user.dart';
import '../../auth/domain/entities/store_membership.dart';
import '../domain/entities/account_transfer.dart';
import '../domain/entities/account_transfer_posting_plan.dart';
import '../domain/repositories/account_transfer_repository.dart';

class AccountTransfersPage extends StatefulWidget {
  const AccountTransfersPage({
    required this.repository,
    required this.user,
    required this.membership,
    super.key,
  });

  final AccountTransferRepository? repository;
  final AuthenticatedUser user;
  final StoreMembership membership;

  @override
  State<AccountTransfersPage> createState() => _AccountTransfersPageState();
}

class _AccountTransfersPageState extends State<AccountTransfersPage> {
  static const _currency = 'ILS';
  static const _accounts = <String, String>{
    '1110': 'الصندوق الرئيسي',
    '1121': 'البنك الرئيسي',
    '1130': 'الشيكات قيد التحصيل',
    '1160': 'ذمم البطاقات',
  };

  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _fromAccountId = '1110';
  String _toAccountId = '1121';
  bool _isPosting = false;

  @override
  Widget build(BuildContext context) {
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
                        const Icon(Icons.swap_horiz_outlined, size: 30),
                        const SizedBox(width: 10),
                        Text(
                          'تحويل بين الحسابات',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'ينقل المبلغ بين حسابين مرحّلين بقيد متوازن دون إنشاء إيراد أو مصروف.',
                    ),
                    const SizedBox(height: 24),
                    DropdownButtonFormField<String>(
                      initialValue: _fromAccountId,
                      decoration: const InputDecoration(
                        labelText: 'من حساب',
                        prefixIcon: Icon(Icons.call_made_outlined),
                      ),
                      items: _accounts.entries
                          .map(
                            (entry) => DropdownMenuItem<String>(
                              value: entry.key,
                              child: Text(entry.value),
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
                                _fromAccountId = value;
                                if (_toAccountId == value) {
                                  _toAccountId =
                                      value == '1110' ? '1121' : '1110';
                                }
                              });
                            },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _toAccountId,
                      decoration: const InputDecoration(
                        labelText: 'إلى حساب',
                        prefixIcon: Icon(Icons.call_received_outlined),
                      ),
                      items: _accounts.entries
                          .where((entry) => entry.key != _fromAccountId)
                          .map(
                            (entry) => DropdownMenuItem<String>(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _isPosting
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _toAccountId = value);
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
                        labelText: 'المبلغ',
                        hintText: '0.00',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descriptionController,
                      enabled: !_isPosting,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'الوصف',
                        hintText: 'مثال: تغذية الصندوق من البنك',
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _isPosting ? null : _postTransfer,
                      icon: _isPosting
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: Text(
                        _isPosting ? 'جارٍ الترحيل...' : 'ترحيل التحويل',
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

  Future<void> _postTransfer() async {
    final repository = widget.repository;
    if (repository == null) {
      _showMessage('مستودع التحويلات غير موصول بهذه البيئة.');
      return;
    }

    if (_fromAccountId == _toAccountId) {
      _showMessage('اختر حسابين مختلفين.');
      return;
    }

    final amount = _parseMoney(_amountController.text);
    if (amount == null || amount.isZero) {
      _showMessage('أدخل مبلغاً صحيحاً أكبر من صفر.');
      return;
    }

    final transferId = 'transfer-${DateTime.now().microsecondsSinceEpoch}';
    final transfer = AccountTransfer(
      id: transferId,
      storeId: widget.membership.storeId,
      idempotencyKey: IdempotencyKey(transferId),
      postedAt: DateTime.now().toUtc(),
      fromAccountId: _fromAccountId,
      toAccountId: _toAccountId,
      amount: amount,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
    );

    setState(() => _isPosting = true);
    final result = await repository.postTransfer(
      context: transfer.contextFor(widget.user.id),
      transfer: transfer,
    );
    if (!mounted) {
      return;
    }
    setState(() => _isPosting = false);

    if (result is FailureResult<AccountTransferPostingPlan>) {
      final failure = result.failure;
      if (failure is QueuedFailure) {
        _showMessage('تم حفظ التحويل للطابور وسيُرحّل عند عودة الاتصال.');
      } else {
        _showMessage(failure.message);
      }
      return;
    }

    if (result is Success<AccountTransferPostingPlan>) {
      _amountController.clear();
      _descriptionController.clear();
      _showMessage('تم ترحيل التحويل والقيد بنجاح.');
    }
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
    _descriptionController.dispose();
    super.dispose();
  }
}
