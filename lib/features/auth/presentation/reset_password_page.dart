import 'package:flutter/material.dart';

import '../../../core/result/result.dart';
import '../application/auth_session_controller.dart';
import 'v1_auth_visuals.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({required this.controller, super.key});
  final AuthSessionController controller;

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isSending = false;
  String? _errorMessage;
  bool _resetRequested = false;

  Future<void> _submit() async {
    if (_isSending || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isSending = true;
      _errorMessage = null;
      _resetRequested = false;
    });
    final result = await widget.controller.sendPasswordResetEmail(
      email: _emailController.text.trim(),
    );
    if (!mounted) return;
    if (result is FailureResult<void>) {
      setState(() {
        _isSending = false;
        _errorMessage = result.failure.message;
      });
      return;
    }
    setState(() {
      _isSending = false;
      _resetRequested = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'إذا كان البريد مسجّلاً، سيصلك رابط إعادة تعيين كلمة المرور. تحقق أيضًا من مجلد الرسائل غير المرغوب فيها (Spam).',
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return V1AuthLayout(
      variant: AuthDecorationVariant.reset,
      title: 'نسيت كلمة المرور؟',
      subtitle: 'أدخل بريدك الإلكتروني لإرسال رابط إعادة تعيين كلمة المرور',
      onBack: () => Navigator.of(context).pop(),
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr,
              autofillHints: const [AutofillHints.email],
              style: TextStyle(fontSize: 16, color: Colors.grey.shade800),
              decoration: V1AuthControls.decoration(
                label: 'البريد الإلكتروني',
                hint: 'example@example.com',
                icon: Icons.email_rounded,
              ),
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty) return 'الرجاء إدخال البريد الإلكتروني';
                if (!email.contains('@')) {
                  return 'الرجاء إدخال بريد إلكتروني صحيح';
                }
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            V1AuthControls.primaryButton(
              label: 'إرسال رابط إعادة التعيين',
              loading: _isSending,
              onPressed: _submit,
            ),
            V1AuthControls.errorBanner(_errorMessage),
            if (_resetRequested) ...[
              const SizedBox(height: 16),
              const Text(
                'تم قبول الطلب. إذا كان البريد مسجّلاً، افحص صندوق الوارد ومجلد Spam.',
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
      footer: TextButton.icon(
        onPressed: _isSending ? null : () => Navigator.of(context).pop(),
        icon: Icon(
          Icons.arrow_back,
          color: Colors.white.withValues(alpha: 0.9),
        ),
        label: Text(
          'العودة لتسجيل الدخول',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }
}
